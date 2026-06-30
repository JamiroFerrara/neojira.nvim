local M = {}
local U = require("./utils")

M.selected_key = ""
M.task_list = ""
M.show_all_assignees = false
M.show_all_statuses = false
M.sort_order = "status"

M.setup = function(config)
	M.username = config.username
	M.browser = config.browser
	vim.api.nvim_set_hl(0, "NeojiraFav", { fg = "#89b4fa", bold = true })
	M.fav_ns = vim.api.nvim_create_namespace("neojira_fav")
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

M.status_order = {
	todo = 1,
	inprog = 2,
	["more info"] = 3,
	r4t = 4,
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
		local rows = {}
		for _, line in ipairs(vim.split(res, "\n")) do
			local cols = vim.split(line, "\t")
			if #cols >= 4 then
				cols[2] = M.status_labels[cols[2]] or cols[2]
				table.insert(rows, cols)
			end
		end

		local widths = { key = 3, status = 6, summary = 7, assignee = 8 }
		for _, cols in ipairs(rows) do
			widths.key = math.max(widths.key, #cols[1])
			widths.status = math.max(widths.status, #cols[2])
			widths.summary = math.max(widths.summary, #cols[3])
			if widths.summary > 80 then widths.summary = 80 end
			widths.assignee = math.max(widths.assignee, #cols[4])
		end

		local fmt_lines = {}
		for _, cols in ipairs(rows) do
			local key     = string.format("%-" .. widths.key .. "s", cols[1])
			local status  = string.format("%-" .. widths.status .. "s", cols[2])
			local summary = cols[3]
			if #summary > 80 then summary = summary:sub(1, 77) .. "..." end
			summary       = string.format("%-" .. widths.summary .. "s", summary)
			local assignee = string.format("%-" .. widths.assignee .. "s", cols[4])
			table.insert(fmt_lines, key .. "   " .. status .. "   " .. summary .. "   " .. assignee)
		end
		res = table.concat(fmt_lines, "\n")
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
local log_file = "/tmp/neojira_today_logs.json"

local function load_logs()
	local f = io.open(log_file, "r")
	if not f then return {} end
	local ok, data = pcall(vim.json.decode, f:read("*a"))
	f:close()
	if not ok or type(data) ~= "table" then return {} end
	return data
end

local function save_logs(logs)
	local f = io.open(log_file, "w")
	if f then
		f:write(vim.json.encode(logs))
		f:close()
	end
end

local fav_file = "/tmp/neojira_favourites.json"

local function load_favs()
	local f = io.open(fav_file, "r")
	if not f then return {} end
	local ok, data = pcall(vim.json.decode, f:read("*a"))
	f:close()
	if not ok or type(data) ~= "table" then return {} end
	local set = {}
	for _, k in ipairs(data) do set[k] = true end
	return set
end

local function save_favs(favs)
	local list = {}
	for k in pairs(favs) do table.insert(list, k) end
	table.sort(list)
	local f = io.open(fav_file, "w")
	if f then
		f:write(vim.json.encode(list))
		f:close()
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

local function status_rank(label)
	local rank = M.status_order[label]
	return rank or 5
end

M.get_all_tasks = function()
	vim.defer_fn(function()
		U.put_text(M.buf_tasks, "Getting jira tasks..🔥")
	end, 100)

	vim.defer_fn(function()
		-- Build JQL with optional assignee filter
		local jql = 'project IS NOT EMPTY AND sprint in openSprints()'
		if not M.show_all_assignees then
			jql = 'assignee = "' .. M.username .. '" AND ' .. jql
		end

		-- Build status exclusions
		local status_filter = ''
		if not M.show_all_statuses then
			status_filter = '-s~Chiuso -s~Risolti'
		end
		local cols = "key,status,summary,assignee"
		if M.sort_order == "recent" then cols = cols .. ",updated" end
		local cmd = "jira issue list --plain --no-headers --columns " .. cols .. " " .. status_filter .. " --jql '" .. jql .. "'"
		local res = vim.fn.system(cmd)

		-- Parse rows into a dict (key -> cols) for dedup
		local rows = {}
		for _, line in ipairs(vim.split(res, "\n")) do
			local raw = vim.split(line, "\t")
			-- Compact: remove empty fields to handle jira CLI cross-project tab padding
			local cols = {}
			for _, v in ipairs(raw) do
				if v ~= "" then table.insert(cols, v) end
			end
			if #cols >= 4 then
				cols[2] = M.status_labels[cols[2]] or cols[2]
				rows[cols[1]] = cols
			end
		end

		-- Fetch favourites (unfiltered) and merge
		local favs = load_favs()
		local fav_keys = {}
		for k in pairs(favs) do table.insert(fav_keys, k) end
		if #fav_keys > 0 then
			local or_clauses = {}
			for _, k in ipairs(fav_keys) do
				table.insert(or_clauses, 'key = "' .. k .. '"')
			end
			local fav_cmd = "jira issue list --plain --no-headers --columns " .. cols .. " --jql '" .. table.concat(or_clauses, " OR ") .. "'"
			local fav_res = vim.fn.system(fav_cmd)
			for _, line in ipairs(vim.split(fav_res, "\n")) do
				local raw = vim.split(line, "\t")
				local ccols = {}
				for _, v in ipairs(raw) do
					if v ~= "" then table.insert(ccols, v) end
				end
				if #ccols >= 4 then
					ccols[2] = M.status_labels[ccols[2]] or ccols[2]
					if not rows[ccols[1]] then
						rows[ccols[1]] = ccols
					end
				end
			end
		end
		local sorted = {}
		for k in pairs(rows) do table.insert(sorted, k) end
		if M.sort_order == "recent" then
			table.sort(sorted, function(a, b)
				local da = rows[a][5] or ""
				local db = rows[b][5] or ""
				if da ~= db then return da > db end
				return a < b
			end)
		else
			table.sort(sorted, function(a, b)
				local ra = status_rank(rows[a][2])
				local rb = status_rank(rows[b][2])
				if ra ~= rb then return ra < rb end
				return a < b
			end)
		end
		-- Load today's logged time
		local today_logs = load_logs()

		-- Compute column widths (including time column before assignee)
		local widths = { key = 3, status = 6, summary = 7, time = 4, assignee = 8 }
		local all_cols = {}
		for _, k in ipairs(sorted) do
			local cols = rows[k]
			cols.time = format_seconds(today_logs[k] or 0)
			table.insert(all_cols, cols)
			widths.key = math.max(widths.key, #cols[1])
			widths.status = math.max(widths.status, #cols[2])
			widths.summary = math.max(widths.summary, #cols[3])
			if widths.summary > 80 then widths.summary = 80 end
			widths.time = math.max(widths.time, #cols.time)
			widths.assignee = math.max(widths.assignee, #cols[4])
		end
		-- Build filter status header
		local all_lbl = M.show_all_assignees and "ON " or "OFF"
		local sts_lbl = M.show_all_statuses and "ON " or "OFF"
		local fav_count = 0
		for _ in pairs(favs) do fav_count = fav_count + 1 end
		local ord_lbl = M.sort_order == "recent" and "recent" or "status"
		local hdr = string.format("[a]ll:%s  [s]tatus:%s  [F]avs:%d  [O]:%s", all_lbl, sts_lbl, fav_count, ord_lbl)
		local sep = string.rep("─", #hdr)

		-- Format lines and track fav line numbers
		local fmt_lines = { hdr, sep }
		local fav_lines = {}  -- 0-indexed buffer line -> true
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
				fav_lines[i + 1] = true  -- +1 for header
			end
		end

		res = table.concat(fmt_lines, "\n")
		M.task_list = res
		U.put_text(M.buf_tasks, res)

		-- Apply highlights to favourite rows
		for line, _ in pairs(fav_lines) do
			vim.api.nvim_buf_add_highlight(M.buf_tasks, M.fav_ns, "NeojiraFav", line, 0, -1)
		end
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
	U.nmap("O", function()
		M.sort_order = (M.sort_order == "status") and "recent" or "status"
		M.get_all_tasks()
	end, M.buf_tasks)
	U.nmap("a", function() M.show_all_assignees = not M.show_all_assignees; M.get_all_tasks() end, M.buf_tasks)
	U.nmap("s", function() M.show_all_statuses = not M.show_all_statuses; M.get_all_tasks() end, M.buf_tasks)
	U.nmap("F", function()
		local line = vim.api.nvim_get_current_line()
		local key = line:match("([A-Z][A-Z0-9]+%-(%d+))")
		if not key then return end
		local favs = load_favs()
		if favs[key] then
			favs[key] = nil
			vim.notify("Unpinned " .. key, 1)
		else
			favs[key] = true
			vim.notify("Pinned " .. key, 1)
		end
		save_favs(favs)
		M.get_all_tasks()
	end, M.buf_tasks)
	-- Number keys for quick time logging (1-9 hours)
	for i = 1, 9 do
		U.nmap(tostring(i), function() M.quick_log_time(i) end, M.buf_tasks)
	end

end
M.issue_time_log = function()

	local line = vim.api.nvim_get_current_line()
	M.selected_key = line:match("([A-Z][A-Z0-9]+%-(%d+))")

	if not M.selected_key then
		vim.notify("No valid task key found in the line. 💔", 1)
		return
	end

	U.split(true)
	local time_buf = U.new_scratch()
	vim.bo[time_buf].filetype = "neojira-time"

	local key = M.selected_key

	local function render()
		local logs = load_logs()
		local total = 0
		for _, sec in pairs(logs) do total = total + sec end

		local lines = {
			"Log time for: " .. key,
			"",
			"Today's total: " .. format_seconds(total),
			"",
		}

		local sorted_keys = {}
		for k in pairs(logs) do table.insert(sorted_keys, k) end
		table.sort(sorted_keys)

		for _, k in ipairs(sorted_keys) do
			table.insert(lines, "  " .. k .. "  " .. format_seconds(logs[k]))
		end

		table.insert(lines, "")
		table.insert(lines, "Select a duration and press <cr> to log:")
		table.insert(lines, "")

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

	local pending_time = ""
	local comment_buf = nil

	local function do_log(time_str, comment)
		local cmd = 'jira issue worklog add ' .. key .. ' "' .. time_str .. '"'
		if comment and comment ~= "" then
			local f = io.open("/tmp/neojira_comment.txt", "w")
			if f then f:write(comment); f:close() end
			cmd = cmd .. " --comment \"$(cat /tmp/neojira_comment.txt)\""
		end
		cmd = cmd .. " --no-input"
		vim.fn.system(cmd)

		local logs = load_logs()
		logs[key] = (logs[key] or 0) + seconds_from_str(time_str)
		save_logs(logs)
		vim.notify("Logged " .. time_str .. " on " .. key, 1)
		-- Close comment window first
		if comment_buf and vim.api.nvim_buf_is_valid(comment_buf) then
			for _, w in ipairs(vim.api.nvim_list_wins()) do
				if vim.api.nvim_win_get_buf(w) == comment_buf then
					vim.api.nvim_win_close(w, true)
					break
				end
			end
		end
		-- Close time window
		for _, w in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_buf(w) == time_buf then
				vim.api.nvim_win_close(w, true)
				break
			end
		end
	end

	local function start_comment(time_str)
		pending_time = time_str

		U.split(true)
		comment_buf = U.new_scratch()
		vim.bo[comment_buf].filetype = "neojira-comment"
		U.put_text(comment_buf, "Comment for " .. key .. " " .. time_str .. " (empty to skip):\n\n")
		vim.api.nvim_win_set_cursor(0, {3, 0})
		vim.cmd("startinsert")

		local function submit_comment()
			local lines = vim.api.nvim_buf_get_lines(comment_buf, 0, -1, false)
			local comment = table.concat(lines, "\n"):gsub("^Comment for .+ %(empty to skip%):\n\n", ""):gsub("^\n*", ""):gsub("\n*$", "")
			do_log(pending_time, comment)
		end

		U.nmap("<cr>", submit_comment, comment_buf)
		U.imap("<cr>", submit_comment, comment_buf)
		U.nmap("q", function() do_log(pending_time, "") end, comment_buf)
	end

	local function log_time()
		local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
		local line_content = vim.api.nvim_buf_get_lines(time_buf, cursor_line - 1, cursor_line, false)[1]
		local time_str = line_content:match("^%s+(.+)")
		if not time_str or time_str == "" then return end
		start_comment(time_str)
	end

	U.nmap("<cr>", log_time, time_buf)
	for i = 1, 8 do
		U.nmap(tostring(i), function() start_comment(i .. "h") end, time_buf)
	end

	local function delete_entry()
		local line = vim.api.nvim_get_current_line()
		local entry_key = line:match("^%s+([A-Z][A-Z0-9]+%-%d+)")
		if not entry_key then return end

		-- Remote delete via Jira API
		local token = os.getenv("JIRA_API_TOKEN")
		if token then
			local email = "j.ferrara@novigo-consulting.it"
			local auth = vim.trim(vim.fn.system("echo -n '" .. email .. ":" .. token .. "' | base64 -w0"))
			local today = os.date("%Y-%m-%d")
			local res = vim.fn.system("curl -s --http1.1 -H 'Authorization: Basic " .. auth .. "' 'https://novigo.atlassian.net/rest/api/3/issue/" .. entry_key .. "/worklog'")
			local ok, wl = pcall(vim.json.decode, res)
			if ok and wl.worklogs then
				for _, entry in ipairs(wl.worklogs) do
					local started = (entry.started or ""):sub(1, 10)
					if started == today and entry.id then
						vim.fn.system("curl -s --http1.1 -X DELETE -H 'Authorization: Basic " .. auth .. "' 'https://novigo.atlassian.net/rest/api/3/issue/" .. entry_key .. "/worklog/" .. entry.id .. "'")
					end
				end
			end
		end

		-- Local removal
		local logs = load_logs()
		logs[entry_key] = nil
		save_logs(logs)
		render()
	end

	local function reset_today()
		vim.ui.input({ prompt = "Delete all today's worklogs from server too? (y/N): " }, function(answer)
			if answer ~= "y" and answer ~= "Y" then return end

			save_logs({})

			local token = os.getenv("JIRA_API_TOKEN")
			if token then
				local email = "j.ferrara@novigo-consulting.it"
				local auth = vim.trim(vim.fn.system("echo -n '" .. email .. ":" .. token .. "' | base64 -w0"))
				local today = os.date("%Y-%m-%d")

				local search = vim.fn.system("curl -s --http1.1 -X POST -H 'Authorization: Basic " .. auth .. "' -H 'Content-Type: application/json' -d '{\"jql\":\"worklogDate >= startOfDay()\",\"fields\":[\"key\"],\"maxResults\":30}' 'https://novigo.atlassian.net/rest/api/3/search/jql'")
				local ok, data = pcall(vim.json.decode, search)
				if ok and data.issues then
					for _, issue in ipairs(data.issues) do
						local res = vim.fn.system("curl -s --http1.1 -H 'Authorization: Basic " .. auth .. "' 'https://novigo.atlassian.net/rest/api/3/issue/" .. issue.key .. "/worklog'")
						local ok2, wl = pcall(vim.json.decode, res)
						if ok2 and wl.worklogs then
							for _, entry in ipairs(wl.worklogs) do
								local started = (entry.started or ""):sub(1, 10)
								if started == today then
									local id = entry.id
									if id then
										vim.fn.system("curl -s --http1.1 -X DELETE -H 'Authorization: Basic " .. auth .. "' 'https://novigo.atlassian.net/rest/api/3/issue/" .. issue.key .. "/worklog/" .. id .. "'")
									end
								end
							end
						end
					end
				end
			end

			vim.notify("Today's time reset", 1)
			render()
		end)
	end

	U.nmap("R", reset_today, time_buf)
	U.nmap("d", delete_entry, time_buf)
	U.nmap("q", function() vim.api.nvim_win_close(0, true) end, time_buf)
end

M.quick_log_time = function(hours)
	local line = vim.api.nvim_get_current_line()
	local key = line:match("([A-Z][A-Z0-9]+%-(%d+))")
	if not key then
		vim.notify("No valid task key found in the line. 💔", 1)
		return
	end

	local time_str = hours .. "h"
	local cmd = 'jira issue worklog add ' .. key .. ' "' .. time_str .. '" --no-input'
	vim.fn.system(cmd)

	local logs = load_logs()
	logs[key] = (logs[key] or 0) + hours * 3600
	save_logs(logs)

	vim.notify("Logged " .. time_str .. " on " .. key, 1)
	M.get_all_tasks()
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
		U.nmap("q", M.open_cached_list, M.buf_tasks)
	else
		vim.notify("No valid task key found in the line. 💔", 1)
	end
end

return M