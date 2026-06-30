--- Comments — add a comment to a Jira issue via an interactive scratch buffer.
local Comments = {}

--- Open a scratch buffer for writing a comment, with <cr> bound to submit.
--- When the user presses <cr>, the buffer content is read and passed to jira:add_comment().
--- @param key string — issue key
--- @param jira table — JiraDataSource instance
--- @param display table — Display module
function Comments.add(key, jira, display)
	if not key or key == "" then
		vim.notify("No valid task key found", 1)
		return
	end

	display.split(true)
	local comment_buf = display.new_scratch()
	vim.api.nvim_command("startinsert")

	local function submit_comment()
		local comment_lines = vim.api.nvim_buf_get_lines(comment_buf, 0, -1, false)
		local comment_text = table.concat(comment_lines, "\n")
		jira.add_comment(key, comment_text)
	end

	display.nmap("<cr>", submit_comment, comment_buf)
end

return Comments
