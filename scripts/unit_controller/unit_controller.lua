require("scripts.unit_controller.order.order")
local Observer = require("scripts.tools.observer")

---@class UnitController
---@field order Order | nil
---@field got_new_order Observer
local UnitController = {}
UnitController.__index = UnitController

---@return UnitController
function UnitController:create()
    local obj = setmetatable({}, self)
    obj.order = nil
    obj.got_new_order = Observer:create()
    return obj
end

---@param order Order
function UnitController:set_order(order)
    self.order = order
    self.got_new_order:emit(order)
end

return UnitController
