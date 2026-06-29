local M = {}
local U = require("./utils")

M.selected_key = ""
M.task_list = ""
M.today_logs = {}  -- key -> seconds logged today

M.setup = function(config)
	M.username = config.username
	M.browser = config.browser
	M.company_name = config.company_name

	vim.api.nvim_create_user_command("Neojira", M.run, {})
end

M.run = function()
	M.buf_tasks = U.new_scratch()
	M.get_all_tasks()
end

M.status_labels = {
	["Aperto"] = "todo",
	["Open"] = "todo",
	["In corso"] = "inprog",
	["In Progress"] = "inprog",
	["On Hold"] = "more info",
	["In attesa"] = "more info",
	["Ready For Test"] = "r4t",
	["Ready for Test"] = "r4t",
}

M.get_all_tasks = function()
	vim.defer_fn(function()
		U.put_text(M.buf_tasks, "Getting jira tasks..🔥")
	end, 100)

	vim.defer_fn(function()
		local jql_query = string.format('assignee = "%s" AND project IS NOT EMPTY AND sprint in openSprints()', M.username)
		local res = vim.fn.system(
			"jira issue list --plain -s~Chiuso -s~Risolti --columns key,status,summary,assignee --jql '" .. jql_query .. "'"
		)
		local lines = vim.split(res, "\n")
		for i, line in ipairs(lines) do
			local cols = vim.split(line, "\t")
			if #cols >= 4 then
				local label = M.status_labels[cols[2]] or cols[2]
				cols[2] = label
				lines[i] = table.concat(cols, "  ")
			end
		end
		res = table.concat(lines, "\n")
		M.task_list = res
		U.put_text(M.buf_tasks, res)
	end, 200)

	U.nmap("<cr>", M.open_task, M.buf_tasks)
	U.nmap("r", M.get_all_tasks, M.buf_tasks)
	U.nmap("<bs>", M.open_cached_list, M.buf_tasks)
	U.nmap("<C-o>", M.open_cached_list, M.buf_tasks)
	U.nmap("<M-o>", M.open_cached_list, M.buf_tasks)
	U.nmap("<leader>q", M.close, M.buf_tasks)
	U.nmap("m", M.issue_move, M.buf_tasks)
	U.nmap("t", M.issue_time_log, M.buf_tasks)
	U.nmap("c", M.issue_comment, M.buf_tasks)
	U.nmap("o", M.issue_open_url, M.buf_tasks)
end

M.issue_open_url = function()
	if M.selected_key == "" then
		local line = vim.api.nvim_get_current_line()
		M.selected_key = line:match("([A-Z][A-Z0-9]+%-(%d+))")
	end

	if M.selected_key and M.selected_key ~= "" then
		vim.fn.system(M.browser .. " https://" .. M.company_name .. ".atlassian.net/browse/" .. M.selected_key)
	else
		vim.notify("No valid task key found in the line. 💔", 1)
	end
end

M.issue_comment = function()
	if M.selected_key == "" then
		local line = vim.api.nvim_get_current_line()
		M.selected_key = line:match("([A-Z][A-Z0-9]+%-(%d+))")
	end
	U.split(true)
	local comment_buf = U.new_scratch()
	vim.api.nvim_command("startinsert")
	-- Create a command to submit the comment
	local function submit_comment()
		-- Get all lines from the comment buffer
		local comment_lines = vim.api.nvim_buf_get_lines(comment_buf, 0, -1, false)
		local comment_text = table.concat(comment_lines, "\n") -- Join lines with newline
		-- Create a temporary file to store the comment
		local temp_file = "/tmp/jira_comment.txt"
		local file = io.open(temp_file, "w")
		if file then
			file:write(comment_text)
			file:close()
		else
			print("Error creating temporary file.")
			return
		end
		-- Execute the command to add the comment using the temporary file
		vim.cmd("terminal jira issue comment add " .. M.selected_key .. " < " .. temp_file)
		vim.cmd("quit")
	end
	-- Map <CR> to submit the comment
	U.nmap("<cr>", submit_comment, comment_buf)
end

M.issue_move = function()
	if M.selected_key == "" then
		local line = vim.api.nvim_get_current_line()
		M.selected_key = line:match("([A-Z][A-Z0-9]+%-(%d+))")
	end

	if M.selected_key and M.selected_key ~= "" then
		U.split(true)
		local move_buf = U.new_scratch()
		vim.cmd("terminal jira issue move " .. M.selected_key)
		vim.api.nvim_buf_set_name(move_buf, "Jira Move")

		--BUG: Not working
		vim.api.nvim_create_autocmd("WinClosed", {
			buffer = move_buf,
			callback = function()
				M.get_all_tasks()
			end,
		})
	else
		vim.notify("No valid task key found in the line. 💔", 1)
	end
end

local function format_seconds(total_sec)
	if total_sec <= 0 then return "0h" end
	local h = math.floor(total_sec / 3600)
	local m = math.floor((total_sec % 3600) / 60)
	if m == 0 then return h .. "h" end
	return h .. "h " .. m .. "m"
end

local function seconds_from_str(str)
	local h = str:match("(%d+)h") or "0"
	local m = str:match("(%d+)m") or "0"
	return tonumber(h) * 3600 + tonumber(m) * 60
end

M.issue_time_log = function()
	if M.selected_key == "" then
		local line = vim.api.nvim_get_current_line()
		M.selected_key = line:match("([A-Z][A-Z0-9]+%-(%d+))")
	end

	if not M.selected_key or M.selected_key == "" then
		vim.notify("No valid task key found in the line. 💔", 1)
		return
	end

	U.split(true)
	local time_buf = U.new_scratch()
	vim.bo[time_buf].filetype = "neojira-time"
	local key = M.selected_key

	local function render()
		local total = 0
		for _, sec in pairs(M.today_logs) do total = total + sec end
		local lines = {
			"Log time for: " .. key,
			"Today's total: " .. format_seconds(total),
			"",
			"Select a duration and press <cr> to log:",
			"",
		}
		for i = 0.5, 8, 0.5 do
			local h = math.floor(i)
			local m = (i - h) * 60
			local label = m == 0 and h .. "h" or h .. "h " .. m .. "m"
			table.insert(lines, "  " .. label)
		end
		table.insert(lines, "")
		table.insert(lines, "Press q to close")
		U.put_text(time_buf, table.concat(lines, "\n"))
	end

	render()

	local function log_time()
		local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
		local line_content = vim.api.nvim_buf_get_lines(time_buf, cursor_line - 1, cursor_line, false)[1]
		local time_str = line_content:match("^%s+(.+)")

		if not time_str or time_str == "" then
			return
		end

		vim.fn.system('jira issue worklog add ' .. key .. ' "' .. time_str .. '" --no-input')
		M.today_logs[key] = (M.today_logs[key] or 0) + seconds_from_str(time_str)
		vim.notify("Logged " .. time_str .. " on " .. key, 1)
		render()
	end

	U.nmap("<cr>", log_time, time_buf)
	U.nmap("q", function() vim.api.nvim_buf_delete(time_buf, {force = true}) end, time_buf)
end

M.open_cached_list = function()
	M.selected_key = ""
	if M.task_list ~= nil then
		U.put_text(M.buf_tasks, M.task_list)
	else
		M.get_all_tasks()
	end
end

M.close = function()
	if M.buf_tasks and vim.api.nvim_buf_is_valid(M.buf_tasks) then
		vim.cmd("bdelete! " .. M.buf_tasks)
		M.buf_tasks = nil
	end
end

M.open_task = function()
	M.task_list = U.get_text(M.buf_tasks)
	local line = vim.api.nvim_get_current_line()
	local key = line:match("([A-Z][A-Z0-9]+%-(%d+))")
	M.selected_key = key

	if key then
		local res = vim.fn.system("jira issue view --plain --comments=10 " .. key)
		U.put_text(M.buf_tasks, res)
	else
		vim.notify("No valid task key found in the line. 💔", 1)
	end
end

return M
