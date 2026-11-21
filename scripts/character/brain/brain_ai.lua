require("scripts.character.brain.order.order")
local Brain = require("scripts.character.brain.brain")

---@class BrainAI : Brain
local BrainAI = setmetatable({}, { __index = Brain })
BrainAI.__index = BrainAI

---@return BrainAI
function BrainAI:create()
    ---@type BrainAI
    local obj = Brain.create(self)
    return obj
end

return BrainAI
