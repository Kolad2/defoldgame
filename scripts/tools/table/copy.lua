---copy
---@param tbl table
---@param callback? fun(value: any): any
---@return table
local function copy(tbl, callback)
    local tbl_copy = {}
    for i, value in ipairs(tbl) do
        if callback then
            tbl_copy[i] = callback(value)
        else
            tbl_copy[i] = value
        end
    end
    return setmetatable(tbl_copy, getmetatable(tbl))
end

return copy
