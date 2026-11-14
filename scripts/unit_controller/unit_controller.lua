---@class UnitController
local UnitController = {}
UnitController.__index = UnitController

---@return UnitController
function UnitController:create()
    local obj = setmetatable({}, self)
    return obj
end

return UnitController
