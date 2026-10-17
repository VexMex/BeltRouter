-- Existing blueprint plans belong to the player. Never clear them to make room.
local GhostGuard = {}

function GhostGuard.isGhost(entity)
    return entity.type == "entity-ghost" or entity.type == "tile-ghost"
        or entity.name == "entity-ghost" or entity.name == "tile-ghost"
end

function GhostGuard.new(surface)
    local footprints = {}
    local guard = {}

    -- Rotate the planned piece's collision box, then move it onto the map.
    -- Factorio's area query also finds large ghosts whose centers are outside it.
    function guard.area(spec)
        local name = spec.inner_name or spec.name
        local direction = spec.direction or defines.direction.north
        footprints[name] = footprints[name] or {}
        local bounds = footprints[name][direction]
        if not bounds then
            local box = prototypes.entity[name].collision_box
            local angle = direction * math.pi / 8
            local cosine, sine = math.cos(angle), math.sin(angle)
            local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
            for _, x in ipairs({box.left_top.x, box.right_bottom.x}) do
                for _, y in ipairs({box.left_top.y, box.right_bottom.y}) do
                    local rx, ry = x * cosine - y * sine, x * sine + y * cosine
                    left, top = math.min(left, rx), math.min(top, ry)
                    right, bottom = math.max(right, rx), math.max(bottom, ry)
                end
            end
            bounds = {left, top, right, bottom}
            footprints[name][direction] = bounds
        end
        return {{spec.position.x + bounds[1], spec.position.y + bounds[2]},
                {spec.position.x + bounds[3], spec.position.y + bounds[4]}}
    end

    function guard.isClear(spec)
        -- Do not filter by force: another player's plans deserve the same protection.
        -- Tile ghosts may coexist with belts; the placement code preserves them too.
        return #surface.find_entities_filtered {
            area = guard.area(spec), type = "entity-ghost", limit = 1
        } == 0
    end

    return guard
end

return GhostGuard
