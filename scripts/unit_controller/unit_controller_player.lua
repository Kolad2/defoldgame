require("scripts.unit_controller.order.order")
local UnitController = require("scripts.unit_controller.unit_controller")

---@class UnitControllerPlayer : UnitController
---@field private input GameInput
local UnitControllerPlayer = setmetatable({}, { __index = UnitController })
UnitControllerPlayer.__index = UnitControllerPlayer


---@param input GameInput
---@return UnitControllerPlayer
function UnitControllerPlayer:create(input)
    ---@type UnitControllerPlayer
    local obj = UnitController.create(self)
    obj.input = input
    obj.input.clicked:subscribe(function(x, y)
        obj:_on_game_input_ground(x, y)
    end)
    return obj
end

---@param x number
---@param y number Floor coordinate corresponding to world Z.
function UnitControllerPlayer:_on_game_input_ground(x, y)
    self:set_order(OrderMovePoint:create(x, y))
end

return UnitControllerPlayer
