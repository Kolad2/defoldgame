--- первый уровнь расширения table
local table = require("scripts.tools.table.table")
local dict = require("scripts.tools.dict.init")

---unique
---@param tbl table
---@return table, dict
local function unique(tbl)
    local index_dict = dict:create()
    local i = 1
    while i <= #tbl do
        local item = tbl[i]
        if not (index_dict:has(item)) then
            index_dict:set(item, i)
            i = i + 1
        else
            table.remove_swap(tbl, i)
        end
    end
    return tbl, index_dict
end

return unique
