---
--- Created by Koladik
--- DateTime: 19.11.2026 23:57
---

local Observer = require("scripts.tools.observer")

---@class MovementController
---@field private unit Character
---@field private path vector3[]
---@field private point_index integer
---@field path_completed Observer
local MovementController = {}
MovementController.__index = MovementController
MovementController.ARRIVAL_DISTANCE = 0.001

--- Replace the route with a copy of the supplied points on the XZ floor.
---@param points vector3[]
function MovementController:set_path(points)
    self:stop()
    for i, point in ipairs(points) do
        self.path[i] = vmath.vector3(point.x, 0, point.z)
    end
end

--- Cancel movement without emitting path_completed.
function MovementController:stop()
    self.path = {}
    self.point_index = 1
end

---@param dt number
---@return boolean moved
function MovementController:update(dt)
    if #self.path == 0 then return false end

    local position = go.get_position(self.unit.id)
    position.y = 0
    local remaining = math.max(0, self.unit.speed) * math.max(0, dt)
    local moved = false
    local direction = nil

    while self.point_index <= #self.path do
        local target = self.path[self.point_index]
        local delta = target - position
        local distance = vmath.length(delta)

        if distance <= self.ARRIVAL_DISTANCE then
            moved = moved or distance > 0
            position = vmath.vector3(target)
            self.point_index = self.point_index + 1
        elseif remaining <= 0 then
            break
        else
            direction = delta / distance
            local step = math.min(remaining, distance)
            position = position + direction * step
            remaining = remaining - step
            moved = true

            if step >= distance then
                position = vmath.vector3(target)
                self.point_index = self.point_index + 1
            else
                break
            end
        end
    end

    go.set_position(position, self.unit.id)
    if direction then
        go.set_rotation(vmath.quat_rotation_y(math.atan2(-direction.x, -direction.z)), self.unit.id)
    end

    if self.point_index > #self.path then
        self:stop()
        self.path_completed:emit()
    end
    return moved
end

---@param unit Character
---@return MovementController
function MovementController:create(unit)
    local obj = setmetatable({}, self)
    obj.unit = unit
    obj.path_completed = Observer:create()
    obj:stop()
    return obj
end

return MovementController
