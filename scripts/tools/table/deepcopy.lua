local copy = require("scripts.tools.table.copy")

---deepcopy
---@param tbl table
---@return table
local function deepcopy(tbl)
    return copy(tbl, function(value)
        if type(value) == "table" then
            local meta = getmetatable(value)
            local copy_value = meta and meta.__deepcopy or deepcopy
            return copy_value(value)
        end
        return value
    end)
end

return deepcopy
