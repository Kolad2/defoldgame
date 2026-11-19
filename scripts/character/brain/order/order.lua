---@class Order
Order = {}
Order.__index = Order

---@return Order
function Order:create()
    local obj = setmetatable({}, self)
    return obj
end

---@class OrderMovePoint : Order
---@field x number Target world X coordinate.
---@field z number Target world Z coordinate on the floor.
OrderMovePoint = setmetatable({}, { __index = Order })
OrderMovePoint.__index = OrderMovePoint

---@param x number
---@param z number
---@return OrderMovePoint
function OrderMovePoint:create(x, z)
    local obj = setmetatable({}, self)
    obj.x = x
    obj.z = z
    return obj
end
