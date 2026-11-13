local Observer = require("scripts.tools.observer")
local TOUCH = hash("touch")

---@class GameInput
---@field pressed Observer
local GameInput = {
    pressed = Observer:create()
}

--- Publishes the Defold action on a mouse press or single touch.
---@param action_id hash|nil
---@param action table
function GameInput:on_input(action_id, action)
    if action_id == TOUCH and action.pressed then
        self.pressed:emit(action)
    end
end

return GameInput

