---@class Order
Order = {}
Order.__index = Order

function Order:create()
    obj = setmetatable({}, self)
end

---@class OrderMovePoint : Order
OrderMovePoint = {}
OrderMovePoint.__index = OrderMovePoint

function OrderMovePoint:create()

end