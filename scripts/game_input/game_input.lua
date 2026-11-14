local Observer = require("scripts.tools.observer")
local UnitControllerPlayer = require("scripts.unit_controller.unit_controller_player")
local TOUCH = hash("touch")

---@class GameInput
--- Click subscribers receive (x, y) on the floor: world X and Z respectively.
---@field clicked Observer
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
    return obj
end

---@return UnitControllerPlayer
function GameInput:create_controller()
    return UnitControllerPlayer:create(self)
end

--- Emit floor coordinates (x, y) on a mouse press or single touch.
--- Floor y corresponds to world Z; world Y is the floor height.
---@param action_id hash|nil
---@param action table
function GameInput:on_input(action_id, action)
    if action_id == TOUCH and action.pressed then
        if action.screen_x == nil or action.screen_y == nil then return end
        local point = self.game.camera.to_world(action.screen_x, action.screen_y)
        if point then
            self.clicked:emit(point.x, point.z)
        end
    end
end

return GameInput

