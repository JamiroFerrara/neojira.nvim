--- Display — buffer creation, column formatting, and text utilities.
local Display = {}

--- Create a new scratch buffer and switch to it.
--- @return integer — buffer handle
function Display.new_scratch()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].buflisted = false
	vim.bo[buf].swapfile = false
	vim.api.nvim_set_current_buf(buf)
	return buf
end

--- Split the current window.
--- @param horizontal boolean — true for horizontal split, false for vertical
function Display.split(horizontal)
	vim.api.nvim_command(horizontal and "split" or "vsplit")
end

--- Replace all text in a buffer.
--- @param buf integer
--- @param text string
function Display.put_text(buf, text)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n"))
end

--- Get all text from a buffer.
--- @param buf integer
--- @return string
function Display.get_text(buf)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	return table.concat(lines, "\n")
end

--- Register a normal-mode keymap for a buffer.
--- @param key string
--- @param func function
--- @param buf integer
function Display.nmap(key, func, buf)
	vim.keymap.set("n", key, func, { buffer = buf, noremap = true, silent = true })
end

--- Register an insert-mode keymap for a buffer.
--- @param key string
--- @param func function
--- @param buf integer
function Display.imap(key, func, buf)
	vim.keymap.set("i", key, func, { buffer = buf, noremap = true, silent = true })
end

--- Map status labels to canonical status groups.
local STATUS_LABELS = {
	["Aperto"] = "todo",
	["Open"] = "todo",
	["In corso"] = "inprog",
	["In Progress"] = "inprog",
	["On Hold"] = "more info",
	["In attesa"] = "more info",
	["Ready For Test"] = "r4t",
	["Ready for Test"] = "r4t",
}

--- Canonical status sort order.
local STATUS_ORDER = {
	todo = 1,
	inprog = 2,
	["more info"] = 3,
	r4t = 4,
}

--- Normalize a status label to a canonical group.
--- @param label string
--- @return string
function Display.normalize_status(label)
	return STATUS_LABELS[label] or label
end

--- Rank a canonical status for sorting.
--- @param label string
--- @return integer
function Display.status_rank(label)
	return STATUS_ORDER[label] or 5
end

--- Format a duration string from total seconds.
--- @param total_sec integer
--- @return string  e.g. "2h 30m"
function Display.format_seconds(total_sec)
	if total_sec <= 0 then return "0h" end
	local h = math.floor(total_sec / 3600)
	local m = math.floor((total_sec % 3600) / 60)
	if m == 0 then return h .. "h" end
	return h .. "h " .. m .. "m"
end

--- Parse a duration string into seconds.
--- @param str string  e.g. "2h 30m"
--- @return integer
function Display.seconds_from_str(str)
	local h = str:match("(%d+)h") or "0"
	local m = str:match("(%d+)m") or "0"
	return tonumber(h) * 3600 + tonumber(m) * 60
end

--- Format a list of task rows into display text with column layout.
---
--- Each row is a table with positional fields: {key, status, summary, assignee}
--- An optional 5th field `updated` is used when sort_order == "recent".
--- An optional `.time` string field is appended before assignee.
---
--- @param rows table[] — list of row arrays
--- @param opts table — { favs? {}, show_all_assignees? bool, show_all_statuses? bool, sort_order? "status"|"recent" }
--- @return string, table  — formatted text, fav_line_numbers (0-indexed -> true)
function Display.format_task_rows(rows, opts)
	opts = opts or {}
	local favs = opts.favs or {}
	local sort_order = opts.sort_order or "status"

	-- Normalize statuses
	for _, cols in ipairs(rows) do
		cols[2] = STATUS_LABELS[cols[2]] or cols[2]
	end

	-- Sort
	local sorted = {}
	for i, cols in ipairs(rows) do
		table.insert(sorted, { cols, i })
	end
	if sort_order == "recent" then
		table.sort(sorted, function(a, b)
			local da = a[1][5] or ""
			local db = b[1][5] or ""
			if da ~= db then return da > db end
			return a[2] < b[2]
		end)
	else
		table.sort(sorted, function(a, b)
			local ra = STATUS_ORDER[a[1][2]] or 5
			local rb = STATUS_ORDER[b[1][2]] or 5
			if ra ~= rb then return ra < rb end
			return a[2] < b[2]
		end)
	end

	-- Compute column widths
	local widths = { key = 3, status = 6, summary = 7, time = 4, assignee = 8 }
	local all_cols = {}
	for _, pair in ipairs(sorted) do
		local cols = pair[1]
		cols.time = cols.time or "0h"
		table.insert(all_cols, cols)
		widths.key = math.max(widths.key, #cols[1])
		widths.status = math.max(widths.status, #cols[2])
		widths.summary = math.max(widths.summary, #cols[3])
		if widths.summary > 80 then widths.summary = 80 end
		widths.time = math.max(widths.time, #cols.time)
		widths.assignee = math.max(widths.assignee, #cols[4])
	end

	-- Build header
	local all_lbl = opts.show_all_assignees and "ON " or "OFF"
	local sts_lbl = opts.show_all_statuses and "ON " or "OFF"
	local fav_count = 0
	for _ in pairs(favs) do fav_count = fav_count + 1 end
	local ord_lbl = sort_order == "recent" and "recent" or "status"
	local hdr = string.format("[a]ll:%s  [s]tatus:%s  [F]avs:%d  [O]:%s", all_lbl, sts_lbl, fav_count, ord_lbl)
	local sep = string.rep("─", #hdr)

	local fmt_lines = { hdr, sep }
	local fav_line_numbers = {}

	for i, cols in ipairs(all_cols) do
		local key     = string.format("%-" .. widths.key .. "s", cols[1])
		local status  = string.format("%-" .. widths.status .. "s", cols[2])
		local summary = cols[3]
		if #summary > 80 then summary = summary:sub(1, 77) .. "..." end
		summary       = string.format("%-" .. widths.summary .. "s", summary)
		local time    = string.format("%-" .. widths.time .. "s", cols.time)
		local assignee = string.format("%-" .. widths.assignee .. "s", cols[4])
		table.insert(fmt_lines, key .. "   " .. status .. "   " .. summary .. "   " .. time .. "   " .. assignee)
		if favs[cols[1]] then
			fav_line_numbers[i + 1] = true  -- +1 for header row
		end
	end

	return table.concat(fmt_lines, "\n"), fav_line_numbers
end

return Display
