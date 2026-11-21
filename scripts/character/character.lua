require("scripts.character.brain.order.order")
local AnimationPlayer = require("scripts.character.animation_player")
local MovementController = require("scripts.character.movement_controller")

---@class Character
---@field id hash
---@field brain Brain
---@field speed number
---@field animation_player AnimationPlayer
---@field movement_controller MovementController
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
    self.movement_controller:stop()
    self.animation_player:set_walking(false)

    if order and getmetatable(order) == OrderMovePoint then
        ---@cast order OrderMovePoint
        -- A future pathfinder can supply the route here instead of one point.
        self.movement_controller:set_path({ order.target_point })
    elseif order and getmetatable(order) == OrderPatrol then
        ---@cast order OrderPatrol
        self.movement_controller:set_path({ order.from_point, order.target_point })
    end
end

---@private
function Character:_on_path_completed()
    local order = self.brain.order
    if order and getmetatable(order) == OrderPatrol then
        ---@cast order OrderPatrol
        self.movement_controller:set_path({ order.from_point, order.target_point })
    elseif order and getmetatable(order) == OrderMovePoint then
        self.brain.order = nil
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
        obj:_on_path_completed()
    end)
    obj.brain.got_new_order:subscribe(function(order)
        obj:_on_new_order(order)
    end)
    obj:_on_new_order(brain.order)
    return obj
end

return Character
