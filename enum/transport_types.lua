-- Shared names used by the routing modules. These are labels, not game entities.
-- Keep piece categories and line categories separate so their meaning stays clear.
-- Original definitions by seancheey (2020), combined without changing their values.

--- @class EntityTransportType: table<string, string>
--- @class TransportLineType: table<string, string>
--- @type {entity: EntityTransportType, line: TransportLineType}
return {
    entity = {
        onGround = "onGround",
        underground = "underground",
        splitter = "splitter",
        pump = "pump",
        pipe = "pipe"
    },
    line = {
        fluidLine = "fluidLine",
        itemLine = "itemLine"
    }
}
