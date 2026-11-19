require("scripts.character.brain.order.order")
local AnimationPlayer = require("scripts.character.animation_player")

local ARRIVAL_DISTANCE = 0.001

---@class Character
---@field id hash
---@field brain Brain
---@field speed number
---@field animation_player AnimationPlayer
local Character = {}
Character.__index = Character

---@param dt number
function Character:update(dt)
    local order = self.brain.order
    if not order or getmetatable(order) ~= OrderMovePoint then
        self.animation_player:set_walking(false)
        return
    end

    ---@cast order OrderMovePoint
    local pos = go.get_position(self.id)
    local target = vmath.vector3(order.x, 0, order.z)
    local delta = target - pos
    local distance = vmath.length(delta)
    if distance <= ARRIVAL_DISTANCE then
        go.set_position(target, self.id)
        self.brain.order = nil
        self.animation_player:set_walking(false)
        return
    end
    local direction = delta / distance
    local step = math.min(self.speed * math.min(dt, 0.1), distance)
    local next_pos = pos + direction * step
    next_pos.y = 0
    local moved = vmath.length_sqr(next_pos - pos) > 0.0000001
    go.set_position(next_pos, self.id)
    if moved then
        go.set_rotation(vmath.quat_rotation_y(math.atan2(-direction.x, -direction.z)), self.id)
    end
    self.animation_player:set_walking(moved)

    if distance <= step + ARRIVAL_DISTANCE then
        go.set_position(target, self.id)
        self.brain.order = nil
        self.animation_player:set_walking(false)
    end
end

---@param id hash
---@param brain Brain
---@return Character
function Character:create(id, brain)
    local obj = setmetatable({}, self)
    obj.id = id
    obj.brain = brain
    obj.speed = 1.0
    obj.animation_player = AnimationPlayer:create(id)
    return obj
end

return Character
