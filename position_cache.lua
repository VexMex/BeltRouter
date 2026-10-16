-- Remember repeated map queries only until the next explicit clear().
-- Numeric x/y keys avoid building coordinate strings for every lookup.
local PositionCache = {}
PositionCache.__index = PositionCache
local missing = {}

-- Each cache belongs to one route and one query function, keeping player/surface
-- contexts separate. A private marker lets us remember nil as well as false.
function PositionCache.new(query)
    assert(type(query) == "function")
    return setmetatable({ query = query, columns = {} }, PositionCache)
end

function PositionCache:get(position)
    local column = self.columns[position.x]
    if not column then
        column = {}
        self.columns[position.x] = column
    end
    local value = column[position.y]
    if value ~= nil then
        if value == missing then
            return nil
        end
        return value
    end
    value = self.query(position)
    column[position.y] = value == nil and missing or value
    return value
end

-- Call before every search batch and again before final route validation.
function PositionCache:clear()
    self.columns = {}
end

return PositionCache
