-- Runtime entry point. Player input selects endpoints, then starts the route search.
-- This file also turns the chosen route into build ghosts and handles waypoint mode.

--belt_old_directions = {
--    north = 0,
--    northeast = 1,
--    east = 2,
--    southeast = 3,
--    south = 4,
--    southwest = 5,
--    west = 6,
--    northwest = 7
--}
belt_old_directions = defines.direction

--- @alias player_index number

--- @type Copier
local Copy = require("copy")
--- @type Logger
local logging = require("logging")
--- @type EntityRoutingAttribute
local EntityRoutingAttribute = require("path_find/entity_routing_attribute")
--- @type AsyncTaskManager
local AsyncTaskManager = require("async_task")
--- @type SelectionQueue
local SelectionQueue = require("selection_queue")
--- @type TransportLineConnector
local TransportLineConnector = require("transport_line_connector")
--- @type boolean
local releaseMode = require("release")

--- @type table<string, boolean> simple table for easy toggling debugging groups
local loggingCategories = {
    reward = false,
    placing = false,
    transportType = false
}

DirectionHelper = require("direction_helper")

--- async task manager for path finder
local taskManager = AsyncTaskManager:new()

--- @type table<player_index, SelectionQueue>
local playerSelectedStartingPositions = {}

--- Used for waypoint mode of recording player's last routing config
--- @type table<player_index, LineConnectConfig>
local playerLastRoutingConfig = {}

-- Choose which development messages are visible, based on release mode.
local function setupLogging()
    for category, enable in pairs(loggingCategories) do
        logging.addCategory(category, releaseMode and false or enable)
    end
    if releaseMode then
        logging.disableCategory(logging.D)
        logging.disableCategory(logging.I)
        logging.disableCategory(logging.V)
    end
end

-- Add a supported piece to this player's start queue, or unselect it if already selected.
local function setStartingTransportLine(player, selectedEntity)
    if not selectedEntity then
        return
    end
    local entityName = selectedEntity.name
    if entityName == "entity-ghost" then
        entityName = selectedEntity.ghost_name
    end
    local transportLineType = EntityRoutingAttribute.from(entityName)
    if transportLineType then
        if playerSelectedStartingPositions[player.index] == nil then
            playerSelectedStartingPositions[player.index] = SelectionQueue:new(player.index)
        end
        if playerSelectedStartingPositions[player.index]:tryRemoveSelectionAtPos(selectedEntity.position) then
            player.print { "info-message.remove-starting-point" }
        else
            playerSelectedStartingPositions[player.index]:push(selectedEntity)
            player.print { "info-message.push-entity" }
            if logging.shouldOutput(logging.D) then
                logging.log("Add entity " .. entityName .. " at position " .. serpent.line(selectedEntity.position))
            end
        end
    end
end

-- Read the player and the piece under the cursor from the input event.
local function triggerSetStartingTransportLine(event)
    local player = game.players[event.player_index]
    local selectedEntity = player.selected
    setStartingTransportLine(player, selectedEntity)
end

--- @param selectedEntity LuaEntity
--- @param player LuaPlayer
--- @param config LineConnectConfig
-- Take the oldest selected start and connect it to the chosen destination.
-- Prepare the game-specific functions the route planner needs for checking and placing pieces.
local function setEndingTransportLine(player, selectedEntity, config)
    local player_index = player.index
    if not selectedEntity then
        return
    end
    local entityName = selectedEntity.name
    if entityName == "entity-ghost" then
        entityName = selectedEntity.ghost_name
    end
    if not EntityRoutingAttribute.from(entityName) then
        return
    end
    -- Take starts in the order the player selected them.
    local startingEntity
    if playerSelectedStartingPositions[player_index] then
        startingEntity = playerSelectedStartingPositions[player_index]:pop()
    end
    if not startingEntity then
        player.print { "error-message.no-starting-point-selected" }
        return
    end
    config.turningPunishment = settings.get_player_settings(player)["turning-punishment"].value
    config.preferGroundModeUndergroundPunishment = settings.get_player_settings(player)["prefer-ground-mode-underground-punishment"].value
    config.preferLongestUnderground = settings.get_player_settings(player)["prefer-longest-underground"].value
    logging.log("preferLongestUnderground = " .. tostring(settings.get_player_settings(player)["prefer-longest-underground"].value))
    if logging.shouldOutput(logging.D) then
        logging.log("build line with config: " .. serpent.line(config))
    end
    local surface = player.surface
    -- Use Factorio's ghost-placement check on a one-tile belt as a general space check.
    -- The force-build option may allow obstacles that can be marked for removal.
    local function canPlace(position)
        local forced = settings.get_player_settings(player)["force-build"].value
        return surface.can_place_entity {
            name = "transport-belt",
            position = position,
            force = player.force,
            build_check_type = defines.build_check_type.ghost_place,
            forced = forced,
        }
    end
    local num = 1
    --- @param entity LuaEntity
    -- Convert one planned placement into an actual game operation.
    local function place(entity)
        -- Work on a copy so placement details do not modify the route stored by the search.
        entity = Copy.deep_copy(entity)
        entity.force = player.force
        -- Normally create ghosts. Real pieces are only placed directly when cheat mode allows it.
        if (not player.cheat_mode or not settings.get_player_settings(player)["cheat-mode-place-real-entity"].value) and entity.name ~= "entity-ghost" and entity.name ~= "speech-bubble" then
            entity.inner_name = entity.name
            entity.name = "entity-ghost"
        end
        entity.player = player
        -- This tells game to raise build event so that the action could potentially be caught by other mods
        entity.raise_built = true
        -- checks for colliding trees/cliffs
        -- Mark nearby colliding objects for removal before creating this piece.
        local collidingEntities = surface.find_entities({ { entity.position.x - 0.4, entity.position.y - 0.4 }, { entity.position.x + 0.4, entity.position.y + 0.4 } })
        if collidingEntities then
            for _, collidingEntity in ipairs(collidingEntities) do
                collidingEntity.order_deconstruction(player.force, player)
            end
        end

        entity.direction = DirectionHelper.convert_direction_reverse(entity.direction)

        surface.create_entity(entity)
        if not releaseMode then
            player.create_local_flying_text { text = tostring(num), position = entity.position, time_to_live = 100000, speed = 0.000001 }
            num = num + 1
        end
    end
    -- Find nearby transport pieces for interference checks, including existing ghosts.
    local function getEntity(position)
        -- radius 0.5 so that we can capture 2-block wide entities like splitter
        for _, entity in pairs(surface.find_entities_filtered { position = position, radius = 0.5 }) do
            -- don't want player/other vehicles to be included
            local real_name = (entity.name == "entity-ghost") and entity.ghost_name or entity.name
            if EntityRoutingAttribute.from(real_name) then
                -- converts ghost entity to normal entity for easier handling
                if entity.name == "entity-ghost" then
                    entity = {
                        name = entity.ghost_name,
                        direction = DirectionHelper.convert_direction(entity.direction),
                        position = entity.position,
                        type = entity.type,
                    }
                end
                return entity
            end
        end
    end
    -- Give the planner the three game callbacks: can place, place, and look up a neighbor.
    local transportLineConstructor = TransportLineConnector.new(canPlace, place, getEntity, taskManager)
    transportLineConstructor:buildTransportLine(startingEntity, selectedEntity, taskManager, config, player)

    -- set player's last routing config
    playerLastRoutingConfig[player_index] = config
end

--- helper function
--- @param config LineConnectConfig
-- Create an input handler with a preset routing mode, such as forbidding underground pieces.
local function triggerSetEndingTransportLineWithConfigHelper(config)
    return function(event)
        local player = game.players[event.player_index]
        setEndingTransportLine(player, player.selected, config)
    end
end

-- Remove a start marker when the selected piece is mined or marked for removal.
local function tryRemoveSelectedStartingPoint(eventWithEntity)
    local player_index = eventWithEntity.player_index
    --- @type LuaEntity
    local entity = eventWithEntity.entity
    if playerSelectedStartingPositions[player_index] and EntityRoutingAttribute.from(entity.name) then
        playerSelectedStartingPositions[player_index]:tryRemoveSelectionAtPos(entity.position)
    end
end

--- @param player LuaPlayer
--- @return LineConnectConfig
-- Choose which routing preferences waypoint mode should use.
local function getWaypointRoutingConfig(player)
    local configSetting = settings.get_player_settings(player)["waypoint-mode-routing-mode"].value
    if configSetting == ("last-mode") then
        local routingConfig = playerLastRoutingConfig[player.index]
        if not routingConfig then
            routingConfig = { allowUnderground = true, preferOnGround = true }
        end
        return routingConfig
    else
        local routingConfigMapping = {
            ["prefer-on-ground-mode"] = { allowUnderground = true, preferOnGround = true },
            ["prefer-underground-mode"] = { allowUnderground = true, preferOnGround = false },
            ["no-underground-mode"] = { allowUnderground = false, preferOnGround = false }
        }
        local routingConfig = routingConfigMapping[configSetting]
        if not routingConfig then
            logging.log("routing config doesn't exist: " .. tostring(configSetting), logging.E)
        end
        return routingConfig
    end
end

-- Toggle automatic chaining; switching it off also clears the selected starts.
local function toggleWaypointMode(event)
    if event.prototype_name and event.prototype_name ~= "toggle-waypoint-mode" then
        return
    end
    local player = game.players[event.player_index]
    local oldToggleValue = player.is_shortcut_toggled("toggle-waypoint-mode")
    player.set_shortcut_toggled("toggle-waypoint-mode", not oldToggleValue)
    if oldToggleValue == true and playerSelectedStartingPositions[event.player_index] then
        playerSelectedStartingPositions[event.player_index]:removeAll()
        player.print { "info-message.clear-all-starting-points" }
    elseif oldToggleValue == false then
        local configSetting = settings.get_player_settings(player)["waypoint-mode-routing-mode"].value
        player.print { "info-message.notify-waypoint-routing-mode", { "string-mod-setting." .. configSetting } }
    end
end

-- When a supported piece is built in waypoint mode, connect to it and make it the next start.
local function tryUseWaypointMode(event)
    local player = game.players[event.player_index]
    if not player.is_shortcut_toggled("toggle-waypoint-mode") then
        return
    end
    --- @type LuaEntity
    local entity = event.entity
    if not entity then
        return
    end
    local routingAttribute = EntityRoutingAttribute.from((entity.name == "entity-ghost") and entity.ghost_name or event.entity.name)
    if not routingAttribute then
        return
    end
    if not playerSelectedStartingPositions[event.player_index] or #playerSelectedStartingPositions[event.player_index] == 0 then
        player.print({ "error-message.select-entity-before-waypoint-mode" })
        return
    end
    setEndingTransportLine(player, event.entity, getWaypointRoutingConfig(player))
    setStartingTransportLine(player, event.entity)
end

-- Clear the shared task queue, stopping pending searches for all players.
local function terminatePathFinding(event)
    taskManager:removeAllTasks()
    game.players[event.player_index].print { "info-message.terminate-path-finding" }
end

-- Connect input/build events to their handlers and let queued searches advance on each tick.
local function main()
    -- Match the custom input names from data.lua to the functions above.
    script.on_event("select-line-starting-point", triggerSetStartingTransportLine)
    script.on_event("build-transport-line", triggerSetEndingTransportLineWithConfigHelper { allowUnderground = true, preferOnGround = false })
    script.on_event("build-transport-line-no-underground", triggerSetEndingTransportLineWithConfigHelper { allowUnderground = false, preferOnGround = true })
    script.on_event("build-transport-line-prefer-ground", triggerSetEndingTransportLineWithConfigHelper { allowUnderground = true, preferOnGround = true })
    script.on_event("toggle-waypoint-mode", toggleWaypointMode)
    script.on_event("terminate-path-finding", terminatePathFinding)
    script.on_event(defines.events.on_player_mined_entity, tryRemoveSelectedStartingPoint)
    script.on_event(defines.events.on_marked_for_deconstruction, tryRemoveSelectedStartingPoint)
    script.on_event(defines.events.on_lua_shortcut, toggleWaypointMode)
    script.on_event(defines.events.on_built_entity, tryUseWaypointMode)

    taskManager:resolveTaskEveryNthTick(1)
    setupLogging()
    -- Used for debugging purpose only with gvv mod
    if script.active_mods["gvv"] then
        require("__gvv__.gvv")()
    end
end

main()
