require("scripts.character.brain.order.order")
local Brain = require("scripts.character.brain.brain")

---@class BrainPlayer : Brain
---@field private input GameInput
local BrainPlayer = setmetatable({}, { __index = Brain })
BrainPlayer.__index = BrainPlayer


---@param input GameInput
---@return BrainPlayer
function BrainPlayer:create(input)
    ---@type BrainPlayer
    local obj = Brain.create(self)
    obj.input = input
    obj.input.clicked:subscribe(function(x, y)
        obj:_on_game_input_ground(x, y)
    end)
    return obj
end

---@param x number
---@param y number Floor coordinate corresponding to world Z.
function BrainPlayer:_on_game_input_ground(x, y)
    self:set_order(OrderMovePoint:create(x, y))
end

return BrainPlayer
