require("scripts.unit_controller.order.order")

local WALK = "Mixamo | Catwalk Walk Forward"
local ARRIVAL_DISTANCE = 0.001

---@class Character
---@field id hash
---@field controller UnitController
---@field speed number
---@field private model_url url
---@field private moving boolean
local Character = {}
Character.__index = Character


---@param moving boolean
function Character:_set_walking(moving)
    if self.moving == moving then return end
    self.moving = moving
    go.set(self.model_url, "playback_rate", moving and 1 or 0)
    if not moving then go.set(self.model_url, "cursor", 0) end
end

---@param dt number
function Character:update(dt)
    local order = self.controller.order
    if not order or getmetatable(order) ~= OrderMovePoint then
        self:_set_walking(false)
        return
    end

    ---@cast order OrderMovePoint
    local pos = go.get_position(self.id)
    local target = vmath.vector3(order.x, 0, order.z)
    local delta = target - pos
    local distance = vmath.length(delta)
    if distance <= ARRIVAL_DISTANCE then
        go.set_position(target, self.id)
        self.controller.order = nil
        self:_set_walking(false)
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
    self:_set_walking(moved)

    if distance <= step + ARRIVAL_DISTANCE then
        go.set_position(target, self.id)
        self.controller.order = nil
        self:_set_walking(false)
    end
end

---@param id hash
---@param controller UnitController
---@return Character
function Character:create(id, controller)
    local obj = setmetatable({}, self)
    obj.id = id
    obj.controller = controller
    obj.speed = 1.0
    obj.model_url = msg.url(nil, id, "model")
    obj.moving = false
    model.play_anim(obj.model_url, WALK, go.PLAYBACK_LOOP_FORWARD, { playback_rate = 0 })
    return obj
end

return Character
