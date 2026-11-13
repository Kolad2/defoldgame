function unpack(tbl, start_pos, end_pos)
    start_pos = start_pos or 1
    end_pos = end_pos or #tbl
    if start_pos <= end_pos then
        return tbl[start_pos], table.unpack(tbl, start_pos + 1, end_pos)
    end
end

return unpack