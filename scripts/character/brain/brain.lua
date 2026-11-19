require("scripts.character.brain.order.order")
local Observer = require("scripts.tools.observer")

---@class Brain
---@field order Order | nil
---@field got_new_order Observer
local Brain = {}
Brain.__index = Brain

---@return Brain
function Brain:create()
    local obj = setmetatable({}, self)
    obj.order = nil
    obj.got_new_order = Observer:create()
    return obj
end

---@param order Order
function Brain:set_order(order)
    self.order = order
    self.got_new_order:emit(order)
end

return Brain
