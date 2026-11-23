---
--- Created by Koladik
--- DateTime: 23.11.2026 22:09
---

local Area = require("scripts.area.area")

---@class DoorArea : Area
---@field door Door
local DoorArea = setmetatable({}, { __index = Area })
DoorArea.__index = DoorArea

---@param id hash
---@param door Door
---@return DoorArea
function DoorArea:create(id, door)
    ---@type DoorArea
    local obj = Area.create(self, id)
    obj.door = door
    return obj
end

return DoorArea
