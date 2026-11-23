local Observer = require("scripts.tools.observer")

---@class Door
---@field location Location
---@field name string
---@field collision_url url
---@field clicked Observer
local Door = {}
Door.__index = Door

---@param location Location
---@param name string
---@param collision_url url
---@return Door
function Door:create(location, name, collision_url)
    ---@type Door
    local obj = setmetatable({}, self)
    obj.location = location
    obj.name = name
    obj.collision_url = collision_url
    obj.clicked = Observer:create()
    return obj
end

return Door
