local M = {}
local U = require("utils")

M.username = "Jamiro Ferrara"
M.selected_key = ""

M.setup = function(config)
	M.username = config.username or M.username
	-- Set up any necessary configurations or initializations here
	-- This function can be used to set up key mappings, autocommands, etc.
end

M.run = function()
	M.buf_tasks = U.new_scratch()
	M.get_all_tasks(M.buf_tasks)
end

M.get_all_tasks = function(buf)
	U.put_text(buf, "Getting jira tasks..")

	vim.defer_fn(function()
		local jql_query = string.format('assignee = "%s" AND project IS NOT EMPTY AND created >= -50d', M.username)
		local res = vim.fn.system(
			"jira issue list --plain -s~Chiuso --columns key,status,summary,assignee --jql '" .. jql_query .. "'"
		)
		M.task_list = res
		U.put_text(buf, res)
	end, 200) -- Delay for 100 milliseconds

	U.nmap("<cr>", M.open_task, buf)
	U.nmap("<bs>", M.open_cached_list, buf)
	U.nmap("<leader>q", M.close, buf)
	U.nmap("m", M.issue_move, buf)
	U.nmap("c", M.issue_comment, buf)
end

M.issue_comment = function()
	if M.selected_key == "" then
		local line = vim.api.nvim_get_current_line()
		M.selected_key = line:match("(%u%u%u%-%d+)")
	end

	U.split(true)
	local comment_buf = U.new_scratch()
	U.nmap("<cr>", function()
		vim.cmd("terminal jira issue comment add " .. M.selected_key .. " '" .. U.get_text(comment_buf) .. "'")
	end, comment_buf)
end

M.issue_move = function()
	local line = vim.api.nvim_get_current_line()
	local key = line:match("(%u%u%u%-%d+)")
	if key then
		vim.cmd("terminal jira issue move " .. key)
	else
		vim.notify("No valid task key found in the line.", 1)
	end
end

M.open_cached_list = function()
	M.selected_key = ""
	if M.task_list ~= nil then
		U.put_text(M.buf_tasks, M.task_list)
	else
		M.get_all_tasks(M.buf_tasks)
	end
end

M.close = function()
	if M.buf_tasks and vim.api.nvim_buf_is_valid(M.buf_tasks) then
		vim.cmd("bdelete! " .. M.buf_tasks)
		M.buf_tasks = nil
	end
end

M.open_task = function()
	local line = vim.api.nvim_get_current_line()
	local key = line:match("(%u%u%u%-%d+)")
	if key then
		M.selected_key = key
		local res = vim.fn.system("jira issue view --plain --comments=10 " .. key)
		U.put_text(M.buf_tasks, res)
	else
		vim.notify("No valid task key found in the line.", 1)
	end
end

return M
