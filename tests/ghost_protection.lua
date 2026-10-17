-- Exercise the real input handlers, search and placement callbacks together.
-- Area queries use rectangles; this is not a substitute for Factorio's collision engine.
return function(test, eq, Support)
    local function scene()
        local env = Support.fresh()
        local objects, handlers, tickHandler = {}, {}
        env.options["turning-punishment"] = 2
        env.options["prefer-ground-mode-underground-punishment"] = 5
        env.options["prefer-longest-underground"] = true
        env.options["force-build"] = true
        env.options["cheat-mode-place-real-entity"] = true
        env.player.index, env.player.force, env.player.cheat_mode = 1, {}, false
        defines.events = {on_player_mined_entity=1,on_marked_for_deconstruction=2,
            on_lua_shortcut=3,on_built_entity=4}
        defines.build_check_type = {ghost_place=1}
        script = {active_mods={},on_event=function(event,handler) handlers[event]=handler end,
            on_nth_tick=function(_,handler) tickHandler=handler end}
        local function drawing()
            local value={valid=true}; value.destroy=function() value.valid=false end
            return value
        end
        rendering={draw_rectangle=drawing,draw_text=drawing}
        local function overlaps(object, area)
            local box = object.box or {{object.position.x-0.4,object.position.y-0.4},
                                       {object.position.x+0.4,object.position.y+0.4}}
            return object.valid and box[1][1] < area[2][1] and box[2][1] > area[1][1]
                and box[1][2] < area[2][2] and box[2][2] > area[1][2]
        end
        function env.object(name, x, y, box, kind)
            local object={valid=true,name=name,type=kind or name,position={x=x,y=y},
                box=box,direction=0,deconCalls=0,tags={keep="blueprint settings"}}
            object.order_deconstruction=function()
                object.deconCalls=object.deconCalls+1
                if object.type=="entity-ghost" or object.type=="tile-ghost" then object.valid=false end
                if env.onDeconstruct then env.onDeconstruct(object) end
            end
            objects[#objects+1]=object
            return object
        end
        function env.ghost(x,y,box,name)
            local object=env.object("entity-ghost",x,y,box)
            object.ghost_name=name or "assembling-machine-2"
            return object
        end
        env.player.surface={
            -- Deliberately allow ghost overlap: the mod must enforce its own protection.
            can_place_entity=function(spec) return env.canPlace(spec.position) end,
            find_entities_filtered=function(spec)
                if not spec.area then
                    local entity=env.getEntity(spec.position)
                    return entity and {entity} or {}
                end
                local found={}
                for _,object in ipairs(objects) do
                    if (not spec.type or object.type==spec.type)
                        and (not spec.force or object.force==spec.force) and overlaps(object,spec.area) then
                        found[#found+1]=object
                        if spec.limit and #found>=spec.limit then break end
                    end
                end
                return found
            end,
            find_entities=function(area)
                local found={}
                for _,object in ipairs(objects) do
                    if overlaps(object,area) then found[#found+1]=object end
                end
                return found
            end,
            create_entity=function(spec)
                if env.failCreate then return nil end
                -- Model the dangerous default: creating pieces can remove overlapping ghosts.
                if not spec.preserve_ghosts_and_corpses then
                    for _,object in ipairs(objects) do
                        if object.type=="entity-ghost" and overlaps(object,
                            {{spec.position.x-0.4,spec.position.y-0.4},{spec.position.x+0.4,spec.position.y+0.4}}) then
                            object.valid=false
                        end
                    end
                end
                env.place(spec)
                if env.onCreate then env.onCreate(spec) end
                return {valid=true}
            end
        }
        game.players={[1]=env.player}
        local Connector=require("transport_line_connector")
        local originalNew=Connector.new
        Connector.new=function(canPlace,place,getEntity,manager,canPlaceSpec)
            env.placeCallback,env.specCallback=place,canPlaceSpec
            env.controlManager=manager
            return originalNew(canPlace,place,getEntity,manager,canPlaceSpec)
        end
        package.loaded.control=nil
        require("control")
        function env.startControl(length, ghostEndpoints, lineName, underground)
            local start=env.entity(0,0,4,lineName)
            local goal=env.entity(length,0,4,lineName)
            if ghostEndpoints then
                for _,entity in ipairs({start,goal}) do
                    entity.ghost_name,entity.name,entity.type=entity.name,"entity-ghost","entity-ghost"
                    objects[#objects+1]=entity
                end
            end
            start.selection_box={left_top={x=0,y=0},right_bottom={x=1,y=1}}
            env.start,env.goal=start,goal
            env.player.selected=start; handlers["select-line-starting-point"]({player_index=1})
            env.player.selected=goal
            handlers[underground and "build-transport-line" or "build-transport-line-no-underground"]({player_index=1})
        end
        function env.controlTick() game.tick=game.tick+1; tickHandler() end
        function env.finishControl()
            local count=0
            while not env.controlManager.taskQueue:isEmpty() do
                count=count+1; assert(count<=1000,"control search did not finish")
                env.controlTick()
            end
        end
        function env.checkProtected(ghost)
            eq(ghost.valid,true); eq(ghost.deconCalls,0)
            eq(ghost.tags.keep,"blueprint settings")
            for _,spec in ipairs(env.placed) do
                eq(spec.preserve_ghosts_and_corpses,true)
                assert(not overlaps(ghost,require("ghost_guard").new(env.player.surface).area(spec)),
                    "a placement overlapped an existing blueprint")
            end
        end
        return env
    end

    test("building ghosts block their full footprint with force build on or off",function()
        for _,forced in ipairs({true,false}) do
            for _,box in ipairs({{{14.1,0.1},{14.9,0.9}},{{13.1,-1.9},{16.9,1.9}},
                    {{14.1,-3.9},{14.9,3.9}},{{10.1,0.1},{18.9,0.9}}}) do
                local env=scene(); env.options["force-build"]=forced
                local ghost=env.ghost(14.5,0.5,box)
                env.startControl(30); env.finishControl()
                assert(#env.placed>0,"expected a detour around the building")
                env.checkProtected(ghost)
            end
        end
    end)

    test("existing belt and pipe ghosts are preserved by belt and pipe routes",function()
        for _,line in ipairs({"transport-belt","pipe"}) do
            for _,planned in ipairs({"transport-belt","pipe"}) do
                local env=scene(); local ghost=env.ghost(14.5,0.5,nil,planned)
                env.startControl(30,false,line); env.finishControl()
                assert(#env.placed>0); env.checkProtected(ghost)
            end
        end
    end)

    test("another force's blueprint is protected and nearby clear tiles remain usable",function()
        local env=scene(); env.startControl(30)
        local ghost=env.ghost(12.5,0.5); ghost.force={name="another force"}
        eq(env.specCallback({name="transport-belt",position={x=12.5,y=0.5},direction=4}),false)
        eq(env.placeCallback({name="transport-belt",position={x=12.5,y=1.5},direction=4}),true)
        eq(#env.placed,1); env.checkProtected(ghost)
    end)

    test("chosen start and destination ghosts remain usable and untouched",function()
        local env=scene(); env.startControl(30,true); env.finishControl()
        eq(#env.placed,29); eq(env.start.valid,true); eq(env.goal.valid,true)
        for _,spec in ipairs(env.placed) do
            assert(spec.position.x>0.5 and spec.position.x<30.5)
        end
    end)

    test("a blueprint added to an old route section cancels before any placement",function()
        local env=scene(); env.startControl(80); env.controlTick()
        local ghost=env.ghost(74.5,0.5)
        env.finishControl(); eq(#env.placed,0); env.checkProtected(ghost)
        eq(env.messages[#env.messages][1],"error-message.route-no-longer-valid")
    end)

    test("placement itself refuses ghosts even if the planner previously allowed the tile",function()
        local env=scene(); env.startControl(30)
        local spec={name="transport-belt",position={x=12.5,y=0.5},direction=4}
        eq(env.specCallback(spec),true)
        local ghost=env.ghost(12.5,0.5)
        eq(env.placeCallback(spec),false); eq(#env.placed,0); env.checkProtected(ghost)
    end)

    test("a ghost added by a deconstruction event is checked before creation",function()
        local env=scene(); env.startControl(30)
        env.object("tree",12.5,0.5)
        local ghost
        env.onDeconstruct=function() ghost=env.ghost(12.5,0.5) end
        eq(env.placeCallback({name="transport-belt",position={x=12.5,y=0.5},direction=4}),false)
        eq(#env.placed,0); env.checkProtected(ghost)
    end)

    test("tile ghosts are preserved while removable natural obstacles still work",function()
        local env=scene(); env.startControl(30)
        local tile=env.object("tile-ghost",12.5,0.5)
        local tree=env.object("tree",12.5,0.5)
        eq(env.placeCallback({name="transport-belt",position={x=12.5,y=0.5},direction=4}),true)
        eq(tile.valid,true); eq(tile.deconCalls,0); eq(tree.deconCalls,1)
        eq(env.placed[1].preserve_ghosts_and_corpses,true)
    end)

    test("real entity placement in cheat mode also preserves blueprints",function()
        local env=scene(); env.player.cheat_mode=true; env.startControl(30)
        local ghost=env.ghost(12.5,0.5)
        eq(env.placeCallback({name="transport-belt",position={x=12.5,y=0.5},direction=4}),false)
        eq(#env.placed,0); env.checkProtected(ghost)
        eq(env.placeCallback({name="transport-belt",position={x=10.5,y=0.5},direction=4}),true)
        eq(env.placed[1].name,"transport-belt"); eq(env.placed[1].preserve_ghosts_and_corpses,true)
    end)

    test("full planned pump footprint is protected in both cardinal orientations",function()
        for _,direction in ipairs({0,4,8,12}) do
            local env=scene(); env.startControl(30)
            local vertical=direction==0 or direction==8
            local ghost=env.ghost(vertical and 12.5 or 13.25,vertical and 1.25 or 0.5,
                vertical and {{12.3,1.1},{12.7,1.4}} or {{13.1,0.3},{13.4,0.7}})
            local spec={name="pump",position={x=12.5,y=0.5},direction=direction}
            eq(env.specCallback(spec),false); eq(env.placeCallback(spec),false)
            eq(#env.placed,0); env.checkProtected(ghost)
        end
    end)

    test("underground routes may pass beneath building plans without replacing them",function()
        local env=scene(); local ghost=env.ghost(14.5,0.5,{{13.1,-0.9},{15.9,1.9}})
        env.startControl(30,false,nil,true); env.finishControl()
        assert(#env.placed>0); env.checkProtected(ghost)
    end)

    test("a ghost added by a build event stops the remaining route placements",function()
        local env=scene(); local ghost
        env.onCreate=function()
            if #env.placed==1 then ghost=env.ghost(2.5,0.5) end
        end
        env.startControl(30); env.finishControl()
        eq(#env.placed,1); env.checkProtected(ghost)
        eq(env.messages[#env.messages][1],"error-message.route-no-longer-valid")
    end)

    test("failed entity creation stops the remaining route placements",function()
        local env=scene(); env.failCreate=true; env.startControl(30); env.finishControl()
        eq(#env.placed,0)
        eq(env.messages[#env.messages][1],"error-message.route-no-longer-valid")
    end)
end
