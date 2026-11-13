local Observer = require("scripts.tools.observer")
local TOUCH = hash("touch")

---@class GameInput
---@field clicked Observer
local GameInput = {}
GameInput.__index = GameInput

---@return GameInput
function GameInput:create()
    ---@type GameInput
    local obj = setmetatable({}, self)
    obj.clicked = Observer:create()
    return obj
end

--- Publishes the Defold action on a mouse press or single touch.
---@param action_id hash|nil
---@param action table
function GameInput:on_input(action_id, action)
    if action_id == TOUCH and action.pressed then
        self.clicked:emit(action)
    end
end

return GameInput

