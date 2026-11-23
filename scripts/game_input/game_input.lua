local Observer = require("scripts.tools.observer")
local BrainPlayer = require("scripts.character.brain.brain_player")
local TOUCH = hash("touch")

---@class GameInput
--- Click subscribers receive (x, y) on the floor: world X and Z respectively.
---@field clicked Observer
---@field picked Observer
---@field private game Game
local GameInput = {}
GameInput.__index = GameInput


---@param game Game
---@return GameInput
function GameInput:create(game)
    ---@type GameInput
    local obj = setmetatable({}, self)
    obj.game = game
    obj.clicked = Observer:create()
    obj.picked = Observer:create()
    return obj
end

---@return BrainPlayer
function GameInput:create_brain()
    return BrainPlayer:create(self)
end

---@param screen_x number
---@param screen_y number
---@return bullet3d.world.cast_result|nil
function GameInput:pick(screen_x, screen_y)
    local world = bullet3d.get_world()
    if not world then return nil end

    local cam = msg.url(self.game.camera.camera_url)
    local from = camera.screen_to_world(
        vmath.vector3(screen_x, screen_y, camera.get_near_z(cam)), cam)
    local to = camera.screen_to_world(
        vmath.vector3(screen_x, screen_y, camera.get_far_z(cam)), cam)

    return bullet3d.world.cast_ray_closest(world, from, to - from)
end

--- Emit floor coordinates (x, y) on a mouse press or single touch.
--- Floor y corresponds to world Z; world Y is the floor height.
---@param action_id hash|nil
---@param action table
function GameInput:on_input(action_id, action)
    if action_id ~= TOUCH or not action.pressed then return end
    if action.screen_x == nil or action.screen_y == nil then return end

    local hit = self:pick(action.screen_x, action.screen_y)
    if hit then
        self.picked:emit(hit)
    end

    local point = self.game.camera.to_world(action.screen_x, action.screen_y)
    if point then
        self.clicked:emit(point.x, point.z)
    end
end

return GameInput

