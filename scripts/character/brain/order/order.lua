---@class Order
Order = {}
Order.__index = Order

---@return Order
function Order:create()
    local obj = setmetatable({}, self)
    return obj
end

---@class OrderMovePoint : Order
---@field target_point vector3 Target world position.
OrderMovePoint = setmetatable({}, { __index = Order })
OrderMovePoint.__index = OrderMovePoint

---@param target_point vector3
---@return OrderMovePoint
function OrderMovePoint:create(target_point)
    local obj = setmetatable({}, self)
    obj.target_point = vmath.vector3(target_point)
    return obj
end

---@class OrderPatrol : Order
---@field from_point vector3 Starting world position.
---@field target_point vector3 Target world position.
OrderPatrol = setmetatable({}, { __index = Order })
OrderPatrol.__index = OrderPatrol

---@param from_point vector3
---@param target_point vector3
---@return OrderPatrol
function OrderPatrol:create(from_point, target_point)
    local obj = setmetatable({}, self)
    obj.from_point = vmath.vector3(from_point)
    obj.target_point = vmath.vector3(target_point)
    return obj
end
