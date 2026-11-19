---
--- Created by Koladik
--- DateTime: 19.11.2026 23:57
---

---@class MovementController
local MovementController = {}
MovementController.__index = MovementController
MovementController.ARRIVAL_DISTANCE = 0.001

---@param dt number
---@param anchor vector3
---@param position vector3
function MovementController:update(dt, anchor, position)
    dt = math.min(dt, 0.1)
    local delta = anchor - position
    local distance = vmath.length(delta)
    if distance <= self.ARRIVAL_DISTANCE then
        self.unit.brain.order = nil
        return
    end
    local direction = delta / distance
    local step = math.min(self.unit.speed * dt, distance)
    local next_position = position + direction * step
    next_position.y = 0
    if distance <= step + self.ARRIVAL_DISTANCE then
        self.unit.brain.order = nil
        return
    end
end

---@return MovementController
function MovementController:create(unit)
    local obj = setmetatable({}, self)
    self.unit = unit
    return obj
end

return MovementController
