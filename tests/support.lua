-- Small Factorio stand-ins for running the actual mod modules under plain Lua 5.2.
-- These tests do not reproduce the game's collision engine or fluid simulation.
local Support = {}
local modules = {
    "vector2d", "direction_helper", "path_find/entity_routing_attribute",
    "path_find/path_segment", "path_find/path_node", "path_find/min_distance_dict",
    "transport_line_connector", "position_cache", "async_task", "minheap", "logging"
}

function Support.fresh()
    for _, name in ipairs(modules) do package.loaded[name] = nil end
    defines = { direction = {
        north = 0, northeast = 2, east = 4, southeast = 6,
        south = 8, southwest = 10, west = 12, northwest = 14
    } }
    belt_old_directions = defines.direction
    prototypes = { entity = {} }
    for _, entry in ipairs({ {"transport-belt"}, {"underground-belt", 5}, {"splitter"} }) do
        prototypes.entity[entry[1]] = {
            name = entry[1], type = entry[1], belt_speed = 0.03125,
            fluid_capacity = 0, max_underground_distance = entry[2]
        }
    end
    prototypes.entity.pipe = { name = "pipe", type = "pipe", fluid_capacity = 100 }
    prototypes.entity["pipe-to-ground"] = {
        name = "pipe-to-ground", type = "pipe-to-ground",
        fluid_capacity = 100, max_underground_distance = 10
    }
    prototypes.entity.pump = { name = "pump", type = "pump", fluid_capacity = 100 }
    local env = {
        messages = {}, placed = {}, blocked = {}, existing = {},
        canCalls = 0, getCalls = 0, serializations = 0, expansions = 0,
        options = {
            ["greedy-level"] = 1.1, ["max-path-finding-explore-num"] = 10000,
            ["path-finding-test-per-tick"] = 15
        }
    }
    serpent = { line = function(_)
        env.serializations = env.serializations + 1
        return "<test value>"
    end }
    game = { tick = 0, print = function(_) end }
    settings = { get_player_settings = function(_)
        local result = {}
        for key, value in pairs(env.options) do result[key] = { value = value } end
        return result
    end }
    env.player = {
        print = function(message) env.messages[#env.messages + 1] = message end,
        create_local_flying_text = function(_) end
    }
    local logging = require("logging")
    for name in pairs(logging.categories) do logging.categories[name] = false end
    logging.addCategory("transportType", false)
    logging.addCategory("placing", false)
    DirectionHelper = require("direction_helper")
    env.Vector = require("vector2d")
    env.Segment = require("path_find/path_segment")
    env.Node = require("path_find/path_node")
    env.Attr = require("path_find/entity_routing_attribute")
    env.manager = require("async_task"):new()
    local function key(position) return position.x .. "|" .. position.y end
    function env.block(x, y, value)
        env.blocked[key({ x = x + 0.5, y = y + 0.5 })] = value ~= false
    end
    function env.entity(x, y, direction, name)
        local value = {
            valid = true, name = name or "transport-belt", direction = direction,
            position = env.Vector.new(x + 0.5, y + 0.5)
        }
        env.existing[key(value.position)] = value
        return value
    end
    function env.canPlace(position)
        env.canCalls = env.canCalls + 1
        return not env.blocked[key(position)] and not env.existing[key(position)]
    end
    function env.getEntity(position)
        env.getCalls = env.getCalls + 1
        return env.existing[key(position)]
    end
    function env.place(spec)
        env.placed[#env.placed + 1] = spec
    end
    env.connector = require("transport_line_connector").new(
        env.canPlace, env.place, env.getEntity, env.manager
    )
    -- Count expansions without changing the planner's ordering or candidates.
    local candidates = env.connector.surroundingCandidates
    env.connector.surroundingCandidates = function(self, ...)
        env.expansions = env.expansions + 1
        return candidates(self, ...)
    end
    function env.begin(sx, sy, tx, ty, underground, name, direction)
        direction = direction or defines.direction.east
        env.start = env.entity(sx, sy, direction, name)
        env.goal = env.entity(tx, ty, direction, name)
        env.connector:buildTransportLine(env.start, env.goal, env.manager, {
            allowUnderground = underground or false, preferOnGround = false,
            preferLongestUnderground = true, turningPunishment = 2
        }, env.player)
    end
    function env.tick()
        game.tick = game.tick + 1
        env.manager:resolveOneTask()
    end
    function env.finish()
        local ticks = 0
        while not env.manager.taskQueue:isEmpty() do
            ticks = ticks + 1
            assert(ticks <= 1000, "search did not stop")
            env.tick()
        end
        return ticks
    end
    function env.signature()
        local values = {}
        for _, spec in ipairs(env.placed) do
            values[#values + 1] = spec.name .. ":" .. key(spec.position) .. ":" .. spec.direction
        end
        return table.concat(values, ";")
    end
    return env
end

return Support
