local M = {}
local U = require("./utils")

M.selected_key = ""
M.task_list = ""

M.setup = function(config)
	M.username = config.username
	M.browser = config.browser
	M.company_name = config.company_name
end

M.run = function()
	M.buf_tasks = U.new_scratch()
	M.get_all_tasks()
end

M.get_all_tasks = function()
	vim.defer_fn(function()
		U.put_text(M.buf_tasks, "Getting jira tasks..🔥")
	end, 100) -- Delay for 100 milliseconds

	vim.defer_fn(function()
		local jql_query = string.format('assignee = "%s" AND project IS NOT EMPTY AND created >= -50d', M.username)
		local res = vim.fn.system(
			"jira issue list --plain -s~Chiuso --columns key,status,summary,assignee --jql '" .. jql_query .. "'"
		)
		M.task_list = res
		U.put_text(M.buf_tasks, res)
	end, 200) -- Delay for 100 milliseconds

	U.nmap("<cr>", M.open_task, M.buf_tasks)
	U.nmap("<bs>", M.open_cached_list, M.buf_tasks)
	U.nmap("<C-o>", M.open_cached_list, M.buf_tasks)
	U.nmap("<M-o>", M.open_cached_list, M.buf_tasks)
	U.nmap("<leader>q", M.close, M.buf_tasks)
	U.nmap("m", M.issue_move, M.buf_tasks)
	U.nmap("c", M.issue_comment, M.buf_tasks)
	U.nmap("o", M.issue_open_url, M.buf_tasks)
end

M.issue_open_url = function()
	if M.selected_key == "" then
		local line = vim.api.nvim_get_current_line()
		M.selected_key = line:match("(%u%u%u%-%d+)")
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
        M.selected_key = line:match("(%u%u%u%-%d+)")
    end
    U.split(true)
    local comment_buf = U.new_scratch()
    vim.api.nvim_command("startinsert")
    -- Create a command to submit the comment
    local function submit_comment()
        -- Get all lines from the comment buffer
        local comment_lines = vim.api.nvim_buf_get_lines(comment_buf, 0, -1, false)
        local comment_text = table.concat(comment_lines, "\n")  -- Join lines with newline
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
		M.selected_key = line:match("(%u%u%u%-%d+)")
	end

	local line = vim.api.nvim_get_current_line()
	local key = line:match("(%u%u%u%-%d+)")
	if key then
		U.split(true)
		local move_buf = U.new_scratch()
		vim.cmd("terminal jira issue move " .. key)
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
	local line = vim.api.nvim_get_current_line()
	local key = line:match("(%u%u%u%-%d+)")
	M.selected_key = key

	if key then
		local res = vim.fn.system("jira issue view --plain --comments=10 " .. key)
		U.put_text(M.buf_tasks, res)
	else
		vim.notify("No valid task key found in the line. 💔", 1)
	end
end

return M
