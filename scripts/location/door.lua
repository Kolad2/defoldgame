local Observer = require("scripts.tools.observer")

---@class Door
---@field location Location
---@field name string
---@field area DoorArea
---@field clicked Observer
local Door = {}
Door.__index = Door

---@param location Location
---@param name string
---@param area DoorArea
---@return Door
function Door:create(location, name, area)
    ---@type Door
    local obj = setmetatable({}, self)
    obj.location = location
    obj.name = name
    obj.area = area
    obj.clicked = Observer:create()
    return obj
end

return Door
