require("scripts.character.brain.order.order")
local AnimationPlayer = require("scripts.character.animation_player")
local MovementController = require("scripts.character.movement_controller")

---@class Character
---@field id hash
---@field brain Brain
---@field speed number
---@field animation_player AnimationPlayer
---@field movement_controller MovementController
---@field private movement_order OrderMovePoint | nil
local Character = {}
Character.__index = Character

---@param dt number
function Character:update(dt)
    local moved = self.movement_controller:update(dt)
    self.animation_player:set_walking(moved)
end

---@private
---@param order Order | nil
function Character:_on_new_order(order)
    self.movement_order = nil
    self.movement_controller:stop()
    self.animation_player:set_walking(false)

    if order and getmetatable(order) == OrderMovePoint then
        ---@cast order OrderMovePoint
        self.movement_order = order
        -- A future pathfinder can supply the route here instead of one point.
        self.movement_controller:set_path({ vmath.vector3(order.x, 0, order.z) })
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
    obj.movement_controller = MovementController:create(obj)
    obj.movement_controller.path_completed:subscribe(function()
        if obj.brain.order == obj.movement_order then
            obj.brain.order = nil
        end
        obj.movement_order = nil
    end)
    obj.brain.got_new_order:subscribe(function(order)
        obj:_on_new_order(order)
    end)
    obj:_on_new_order(brain.order)
    return obj
end

return Character
