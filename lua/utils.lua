local M = {}

---Creates a new scratch buffer.
---@param horizontal boolean
---@return integer
M.new_scratch = function()
    local buf = vim.api.nvim_create_buf(false, true) -- Create a new scratch buffer
    vim.bo[buf].buftype = "nofile" -- set buffer type to nofile
    vim.bo[buf].buflisted = false -- do not list this buffer in the buffer list
    vim.bo[buf].swapfile = false -- disable swap file for this buffer

    vim.api.nvim_set_current_buf(buf) -- switch to the new buffer
    return buf
end

M.split = function(horizontal)
    if horizontal then
        vim.api.nvim_command("split") -- Create a horizontal split
    else
        vim.api.nvim_command("vsplit") -- Create a vertical split
    end
end

M.nmap = function(key, func, buf)
    vim.keymap.set("n", key, func, { buffer = buf, noremap = true, silent = true })
end

M.imap = function(key, func, buf)
    vim.keymap.set("i", key, func, { buffer = buf, noremap = true, silent = true })
end

M.vmap = function(key, func, buf)
    vim.keymap.set("v", key, func, { buffer = buf, noremap = true, silent = true })
end

M.put_text = function(buffer, text)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.split(text, "\n"))
end

M.get_text = function(buffer)
    --gets all text from buffer
    local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
    return table.concat(lines, "\n")
end

return M
