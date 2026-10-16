-- Run from the repository root: lua tests/run.lua (Lua 5.2).
package.path = "./?.lua;./?/init.lua;" .. package.path
local Support = require("tests/support")
local total = 0
local function test(name, fn)
    fn()
    total = total + 1
    print("PASS " .. name)
end
local function eq(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

test("all compass directions round-trip and return independent vectors", function()
    local env = Support.fresh()
    local expected = { [0]={0,-1}, [2]={1,-1}, [4]={1,0}, [6]={1,1},
        [8]={0,1}, [10]={-1,1}, [12]={-1,0}, [14]={-1,-1} }
    local calls, new = 0, env.Vector.new
    env.Vector.new = function(...) calls = calls + 1; return new(...) end
    for direction, coordinates in pairs(expected) do
        local value = env.Vector.fromDirection(direction)
        eq(value.x, coordinates[1]); eq(value.y, coordinates[2])
        eq(value:toDirection(), direction)
        value.x = 99
        eq(env.Vector.fromDirection(direction).x, coordinates[1])
    end
    eq(calls, 16) -- Exactly one vector per valid lookup, not eight.
    eq(env.Vector.fromDirection(1), nil)
    eq(env.Vector.new(2, 2):toDirection(), nil)
end)

test("position cache remembers false, nil and fractional coordinates", function()
    Support.fresh()
    local calls, value = 0, false
    local Cache = require("position_cache")
    local cache = Cache.new(function(_) calls = calls + 1; return value end)
    local position = { x = -0.5, y = 1.5 }
    eq(cache:get(position), false); eq(cache:get(position), false); eq(calls, 1)
    value = nil; cache:clear()
    eq(cache:get(position), nil); eq(cache:get(position), nil); eq(calls, 2)
    value = "new"; cache:clear(); eq(cache:get(position), "new"); eq(calls, 3)
    eq(cache:get({ x = -0.5, y = 2.5 }), "new"); eq(calls, 4)
end)

test("world caches belong to individual connectors and refresh explicitly", function()
    local env = Support.fresh()
    local position = env.Vector.new(4.5, 4.5)
    eq(env.connector.canPlaceEntityFunc(position), true)
    env.block(4, 4)
    eq(env.connector.canPlaceEntityFunc(position), true)
    env.connector.resetWorldCache()
    eq(env.connector.canPlaceEntityFunc(position), false)
    local other = require("transport_line_connector").new(function(_) return true end,
        function(_) end, function(_) return nil end, env.manager)
    eq(other.canPlaceEntityFunc(position), true)
    eq(env.connector.getEntityFunc(position), nil)
    local entity = env.entity(4, 4, 4)
    eq(env.connector.getEntityFunc(position), nil)
    env.connector.resetWorldCache(); eq(env.connector.getEntityFunc(position), entity)
end)

test("prototype descriptions and resolved family prototypes are reused", function()
    local env = Support.fresh()
    local a = env.Attr.from("transport-belt")
    eq(env.Attr.from("transport-belt"), a)
    eq(a.groundEntityPrototype, prototypes.entity["transport-belt"])
    eq(rawget(a, "groundEntityPrototype"), prototypes.entity["transport-belt"])
    eq(a.undergroundEntityPrototype, prototypes.entity["underground-belt"])
    eq(rawget(a, "undergroundEntityPrototype"), prototypes.entity["underground-belt"])
    eq(env.Attr.from("unknown-piece"), nil); eq(env.Attr.from("unknown-piece"), nil)
    eq(env.serializations, 0)
end)

test("enabled transport logging still formats an uncached description", function()
    local env = Support.fresh()
    require("logging").enableCategory("transportType")
    env.Attr.from("transport-belt"); eq(env.serializations, 1)
    env.Attr.from("transport-belt"); eq(env.serializations, 1)
end)

test("all cardinal corners and U-turns use the 16-direction scheme", function()
    local env = Support.fresh()
    for _, direction in ipairs({ 0, 4, 8, 12 }) do
        local function segment(d)
            return env.Segment:new { name="transport-belt", position=env.Vector.new(0.5,0.5), direction=d, distance=1 }
        end
        local root = env.Node:new(segment(direction))
        local right = env.Node:new(segment((direction+4)%16), root)
        eq(right.rightCumulativeTurns, 1); eq(right.leftCumulativeTurns, 0)
        eq(right.enforceCollisionCheck, false)
        local left = env.Node:new(segment((direction+12)%16), root)
        eq(left.leftCumulativeTurns, 1); eq(left.enforceCollisionCheck, false)
        eq(env.Node:new(segment((direction+8)%16), root).enforceCollisionCheck, true)
        local twice = env.Node:new(segment((direction+8)%16), right)
        eq(twice.enforceCollisionCheck, false)
        eq(env.Node:new(segment((direction+12)%16), twice).enforceCollisionCheck, true)
    end
end)

test("pump and splitter footprints cover exactly two tiles on the correct axis", function()
    local env = Support.fresh()
    for _, direction in ipairs({0,4,8,12}) do
        for _, name in ipairs({"pump","splitter"}) do
            local horizontal = (name=="pump" and direction%8==4) or (name=="splitter" and direction%8==0)
            local center = env.Vector.new(horizontal and 0 or 0.5, horizontal and 0.5 or 0)
            local positions = env.Attr.from(name):getAllPointPositions(center, direction)
            eq(#positions, 2)
            eq(math.abs(positions[2].x-positions[1].x), horizontal and 1 or 0)
            eq(math.abs(positions[2].y-positions[1].y), horizontal and 0 or 1)
        end
    end
end)

test("crossing underground belts are not mistaken for parallel connections", function()
    local env = Support.fresh()
    local unit = env.Segment:new {name="underground-belt",position=env.Vector.new(0.5,0.5),direction=4,distance=4}
    local node = env.Node:new(unit)
    local start = env.Segment:new {name="transport-belt",position=env.Vector.new(-5.5,0.5),direction=4,distance=1}
    local goal = env.Segment:new {name="transport-belt",position=env.Vector.new(8.5,0.5),direction=4,distance=1}
    local neighbor = {name="underground-belt",direction=0,position=env.Vector.new(1.5,0.5),belt_to_ground_type="input"}
    env.connector.getEntityFunc = function(p) if p==neighbor.position then return neighbor end end
    eq(env.connector:testCanPlace(node,nil,start,goal,true), true)
    neighbor.direction=4
    eq(env.connector:testCanPlace(node,nil,start,goal,true), false)
    neighbor.direction=12
    eq(env.connector:testCanPlace(node,nil,start,goal,true), false)
end)

test("the search respects the unchanged 15-step batch setting", function()
    local env = Support.fresh()
    env.begin(0,0,80,0,false)
    env.tick(); eq(env.expansions,15); eq(#env.placed,0)
    local previous=env.expansions
    while not env.manager.taskQueue:isEmpty() do
        env.tick(); assert(env.expansions-previous<=15); previous=env.expansions
    end
    eq(#env.placed,79); eq(game.tick,6)
    eq(env.expansions,79) -- No successor generation after reaching the start.
    eq(env.options["path-finding-test-per-tick"],15)
end)

test("final validation catches a newly blocked old section before placing any pieces", function()
    local env = Support.fresh()
    env.begin(0,0,80,0,false)
    env.tick()
    env.block(74,0) -- This part of the backward route was already explored.
    env.finish()
    eq(#env.placed,0)
    eq(env.messages[#env.messages][1],"error-message.route-no-longer-valid")
end)

test("final validation rejects an interfering belt beside an old section", function()
    local env = Support.fresh()
    env.begin(0,0,80,0,false); env.tick()
    env.entity(74,-1,8) -- Points south into the already planned route.
    env.finish(); eq(#env.placed,0)
    eq(env.messages[#env.messages][1],"error-message.route-no-longer-valid")
end)

test("a deleted endpoint ends a queued search without placing ghosts", function()
    for _, endpoint in ipairs({"start","goal"}) do
        local env = Support.fresh()
        env.begin(0,0,80,0,false); env.tick(); env[endpoint].valid=false
        env.finish(); eq(#env.placed,0)
        eq(env.messages[#env.messages][1], endpoint=="start" and "error-message.starting-entity-not-valid" or "error-message.ending-entity-not-valid")
    end
end)

test("a rotated endpoint cancels the stale connection", function()
    local env=Support.fresh()
    env.begin(0,0,80,0,false); env.tick(); env.goal.direction=8
    env.finish(); eq(#env.placed,0)
    eq(env.messages[#env.messages][1],"error-message.route-no-longer-valid")
end)

test("surface belts connect correctly in all four directions", function()
    for _, case in ipairs({{0,-30,0},{30,0,4},{0,30,8},{-30,0,12}}) do
        local env = Support.fresh()
        env.begin(0,0,case[1],case[2],false,nil,case[3]); env.finish()
        eq(#env.placed,29)
        for _, spec in ipairs(env.placed) do eq(spec.direction,case[3]) end
    end
end)

test("underground-enabled belt routing and surface pipe routing still finish", function()
    local env=Support.fresh()
    env.begin(0,0,40,0,true); env.finish(); assert(#env.placed>0)
    local found=false
    for _,spec in ipairs(env.placed) do if spec.name=="underground-belt" then found=true end end
    assert(found,"no underground pairs placed")
    env=Support.fresh()
    env.begin(0,0,20,0,false,"pipe"); env.finish(); eq(#env.placed,19)
end)

test("control entry point connects player selections and places ghosts", function()
    local env=Support.fresh()
    -- Do not let test globals hide a missing dependency in the game entry point.
    DirectionHelper=nil
    belt_old_directions=nil
    defines.events={on_player_mined_entity=1,on_marked_for_deconstruction=2,
        on_lua_shortcut=3,on_built_entity=4}
    defines.build_check_type={ghost_place=1}
    local handlers, tickHandler={}
    script={active_mods={},on_event=function(event,handler) handlers[event]=handler end,
        on_nth_tick=function(interval,handler) eq(interval,1); tickHandler=handler end}
    local function drawing()
        local result={valid=true}
        result.destroy=function() result.valid=false end
        return result
    end
    rendering={draw_rectangle=function(_) return drawing() end,
        draw_text=function(_) return drawing() end}
    env.options["turning-punishment"]=2
    env.options["prefer-ground-mode-underground-punishment"]=5
    env.options["prefer-longest-underground"]=true
    env.options["force-build"]=true
    env.options["cheat-mode-place-real-entity"]=true
    env.player.index=1; env.player.force={}; env.player.cheat_mode=false
    env.player.surface={
        can_place_entity=function(spec) return env.canPlace(spec.position) end,
        find_entities_filtered=function(spec)
            local entity=env.getEntity(spec.position)
            return entity and {entity} or {}
        end,
        find_entities=function(_) return {} end,
        create_entity=function(spec) env.place(spec) end
    }
    game.players={[1]=env.player}
    package.loaded.control=nil
    require("control")
    eq(require("logging").releaseMode,true)
    eq(DirectionHelper,nil); eq(belt_old_directions,nil)
    local start=env.entity(0,0,4)
    start.selection_box={left_top={x=0,y=0},right_bottom={x=1,y=1}}
    local goal=env.entity(30,0,4)
    env.player.selected=start
    handlers["select-line-starting-point"]({player_index=1})
    env.player.selected=goal
    handlers["build-transport-line-no-underground"]({player_index=1})
    eq(#env.placed,0)
    for tick=1,2 do game.tick=tick; tickHandler() end
    eq(#env.placed,29)
    for _,spec in ipairs(env.placed) do
        eq(spec.name,"entity-ghost"); eq(spec.inner_name,"transport-belt")
        eq(spec.direction,4); eq(spec.force,env.player.force); eq(spec.raise_built,true)
    end
end)

print("Passed " .. total .. " tests.")
