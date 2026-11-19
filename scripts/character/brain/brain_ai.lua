require("scripts.character.brain.order.order")

---@class BrainAI : Brain
local BrainAI = {}
BrainAI.__index = BrainAI

---@return BrainAI
function BrainAI:create()
    local obj = setmetatable({}, self)
    return obj
end

return BrainAI
