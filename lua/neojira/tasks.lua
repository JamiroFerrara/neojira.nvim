--- Tasks — fetch, display, and navigate the Jira issue list.
local Tasks = {}
local CACHE_DIR = vim.fn.stdpath("data") .. "/neojira"
local CACHE_FILE = CACHE_DIR .. "/task_cache.json"

--- Persist the rendered task list to disk for fast startup.
--- @param text string
function Tasks._save_cache(text)
	vim.fn.mkdir(CACHE_DIR, "p")
	local f = io.open(CACHE_FILE, "w")
	if f then
		f:write(vim.json.encode({ cached_at = os.date("%Y-%m-%dT%H:%M:%S"), text = text }))
		f:close()
	end
end

--- Load the cached task list. Returns the cached text or nil.
--- @return string|nil
function Tasks.load_cache()
	local f = io.open(CACHE_FILE, "r")
	if not f then return nil end
	local ok, data = pcall(vim.json.decode, f:read("*a"))
	f:close()
	if not ok or type(data) ~= "table" or not data.text then return nil end
	return data.text
end

--- Extract issue key from the current buffer line.
--- @return string|nil
function Tasks._extract_key()
	local line = vim.api.nvim_get_current_line()
	return line:match("([A-Z][A-Z0-9]+%-(%d+))")
end

--- Fetch tasks and populate the issue list buffer.
---
--- Runs the JQL query, merges favourited issues (even when filtered out),
--- formats the display, and applies highlights.
---
--- @param state table — mutable state: { show_all_assignees, show_all_statuses, sort_order, buf_tasks, task_list, selected_key, fav_ns, username, favs_persist, logs_persist }
--- @param deps table — { jira, display, favs }
function Tasks.fetch_all(state, deps)
	if not state.buf_tasks then return end

	vim.defer_fn(function()
		-- Only show loading if no cached content is already displayed
		local current = vim.api.nvim_buf_get_lines(state.buf_tasks, 0, 1, false)
		if not current or #current == 0 or current[1] == "" then
			deps.display.put_text(state.buf_tasks, "Getting jira tasks..🔥")
		end
	end, 100)

	-- Build JQL
	local jql = 'project IS NOT EMPTY AND sprint in openSprints()'
	if not state.show_all_assignees then
		jql = 'assignee = "' .. state.username .. '" AND ' .. jql
	end

	-- Build status exclusions
	local status_filter = ''
	if not state.show_all_statuses then
		status_filter = '-s~Chiuso -s~Risolti'
	end

	local cols = "key,status,summary,assignee"
	if state.sort_order == "recent" then cols = cols .. ",updated" end

	-- Helper: parse tab-separated output into a keyed dict
	local function parse_results(res, target)
		for _, line in ipairs(vim.split(res, "\n")) do
			local raw = vim.split(line, "\t")
			local cols_arr = {}
			for _, v in ipairs(raw) do
				if v ~= "" then table.insert(cols_arr, v) end
			end
			if #cols_arr >= 4 then
				cols_arr[2] = deps.display.normalize_status(cols_arr[2])
				if not target[cols_arr[1]] then
					target[cols_arr[1]] = cols_arr
				end
			end
		end
	end


	local function render(rows, favs)
		-- Build sorted list
		local sorted = {}
		for k in pairs(rows) do table.insert(sorted, k) end
		if state.sort_order == "recent" then
			table.sort(sorted, function(a, b)
				local da = rows[a][5] or ""
				local db = rows[b][5] or ""
				if da ~= db then return da > db end
				return a < b
			end)
		else
			table.sort(sorted, function(a, b)
				local ra = deps.display.status_rank(rows[a][2])
				local rb = deps.display.status_rank(rows[b][2])
				if ra ~= rb then return ra < rb end
				return a < b
			end)
		end

		-- Load today's logged time (keys are "YYYY-MM-DD:ISSUE-KEY")
		local today_prefix = os.date("%Y-%m-%d") .. ":"
		local today_logs = {}
		for k, v in pairs(state.logs_persist:all()) do
			if k:sub(1, #today_prefix) == today_prefix then
				local issue_key = k:sub(#today_prefix + 1)
				today_logs[issue_key] = v
			end
		end

		-- Add time column
		local all_cols = {}
		for _, k in ipairs(sorted) do
			local cols = rows[k]
			cols.time = deps.display.format_seconds(today_logs[k] or 0)
			table.insert(all_cols, cols)
		end

		-- Format display
		local text, fav_lines = deps.display.format_task_rows(all_cols, {
			favs = favs,
			show_all_assignees = state.show_all_assignees,
			show_all_statuses = state.show_all_statuses,
			sort_order = state.sort_order,
		})

		state.task_list = text
		deps.display.put_text(state.buf_tasks, text)
		Tasks._save_cache(text)

		-- Apply highlights to favourite rows
		for line, _ in pairs(fav_lines) do
			vim.api.nvim_buf_add_highlight(state.buf_tasks, state.fav_ns, "NeojiraFav", line, 0, -1)
		end
	end
	-- Run main query async
	deps.jira.list_issues_async(jql, cols, status_filter, function(res)
		local rows = {}
		parse_results(res, rows)

		-- Fetch favourites and merge (even when filtered out by status/assignee)
		local favs = deps.favs.get_all(state.favs_persist)
		local fav_keys = {}
		for k in pairs(favs) do table.insert(fav_keys, k) end

		if #fav_keys > 0 then
			local or_clauses = {}
			for _, k in ipairs(fav_keys) do
				table.insert(or_clauses, 'key = "' .. k .. '"')
			end
			deps.jira.list_issues_async(table.concat(or_clauses, " OR "), cols, "", function(fav_res)
				parse_results(fav_res, rows)
				render(rows, favs)
			end)
		else
			render(rows, favs)
		end
	end)

end

--- Load cached task list for instant display, then refresh asynchronously.
--- @param state table
--- @param deps table
function Tasks.fetch_cached(state, deps)
	local cached = Tasks.load_cache()
	if cached and cached ~= "" then
		state.task_list = cached
		deps.display.put_text(state.buf_tasks, cached)
	end
	Tasks.fetch_all(state, deps)
end

--- Register all keymaps for the task list buffer.
--- @param state table
--- @param deps table — { jira, display, comments, time, favs }
function Tasks.register_keymaps(state, deps)
	local buf = state.buf_tasks
	if not buf then return end

	deps.display.nmap("<cr>", function() Tasks.open_task(state, deps) end, buf)
	deps.display.nmap("r", function() Tasks.fetch_all(state, deps) end, buf)
	deps.display.nmap("<C-r>", function() Tasks.fetch_all(state, deps) end, buf)
	deps.display.nmap("<bs>", function() Tasks.open_cached(state, deps) end, buf)
	deps.display.nmap("<C-o>", function() Tasks.open_cached(state, deps) end, buf)
	deps.display.nmap("<M-o>", function() Tasks.open_cached(state, deps) end, buf)
	deps.display.nmap("<leader>q", function() Tasks.close(state) end, buf)
	deps.display.nmap("m", function() Tasks.move_issue(state, deps) end, buf)
	deps.display.nmap("t", function() Tasks.time_log(state, deps) end, buf)
	deps.display.nmap("c", function() Tasks.comment(state, deps) end, buf)
	deps.display.nmap("o", function() Tasks.open_url(state, deps) end, buf)
	deps.display.nmap("O", function()
		state.sort_order = (state.sort_order == "status") and "recent" or "status"
		Tasks.fetch_all(state, deps)
	end, buf)
	deps.display.nmap("a", function()
		state.show_all_assignees = not state.show_all_assignees
		Tasks.fetch_all(state, deps)
	end, buf)
	deps.display.nmap("s", function()
		state.show_all_statuses = not state.show_all_statuses
		Tasks.fetch_all(state, deps)
	end, buf)
	deps.display.nmap("F", function()
		deps.favs.toggle(state.favs_persist, function()
			Tasks.fetch_all(state, deps)
		end)
	end, buf)
	deps.display.nmap("/", function() Tasks.search_issues(state, deps) end, buf)

	-- Number keys for quick time logging (1-9 hours)
	for i = 1, 9 do
		deps.display.nmap(tostring(i), function()
			local key = Tasks._extract_key()
			deps.time.quick_log(key, i, deps.jira, state.logs_persist, function()
				Tasks.fetch_all(state, deps)
			end)
		end, buf)
	end
end

--- Open a task detail view.
--- Caches the current list text first, then shows the issue detail.
--- @param state table
--- @param deps table
function Tasks.open_task(state, deps)
	state.task_list = deps.display.get_text(state.buf_tasks)
	local key = Tasks._extract_key()
	state.selected_key = key

	if key then
		local res = deps.jira.view_issue(key, 10)
		deps.display.put_text(state.buf_tasks, res)
		deps.display.nmap("q", function() Tasks.open_cached(state, deps) end, state.buf_tasks)
	else
		vim.notify("No valid task key found in the line. 💔", 1)
	end
end

--- Restore the cached task list.
--- @param state table
--- @param deps table
function Tasks.open_cached(state, deps)
	state.selected_key = ""
	if state.task_list then
		deps.display.put_text(state.buf_tasks, state.task_list)
	else
		Tasks.fetch_all(state, deps)
	end
end

--- Close the task list buffer.
--- @param state table
function Tasks.close(state)
	if state.buf_tasks and vim.api.nvim_buf_is_valid(state.buf_tasks) then
		vim.cmd("bdelete! " .. state.buf_tasks)
		state.buf_tasks = nil
	end
end

--- Open the selected issue in the browser.
--- @param state table
--- @param deps table
function Tasks.open_url(state, deps)
	local key = state.selected_key
	if key == "" then
		key = Tasks._extract_key()
		state.selected_key = key
	end

	if key and key ~= "" then
		deps.jira.open_in_browser(key)
	else
		vim.notify("No valid task key found in the line. 💔", 1)
	end
end

--- Open the comment editor for the selected issue.
--- @param state table
--- @param deps table
function Tasks.comment(state, deps)
	local key = state.selected_key
	if key == "" then
		key = Tasks._extract_key()
		state.selected_key = key
	end
	deps.comments.add(key, deps.jira, deps.display)
end

--- Open the move transition terminal for the selected issue.
--- @param state table
--- @param deps table
function Tasks.move_issue(state, deps)
	local key = state.selected_key
	if key == "" then
		key = Tasks._extract_key()
		state.selected_key = key
	end

	if key and key ~= "" then
		deps.jira.move_issue(key)

		-- When the move terminal closes, refresh the task list
		local last_buf = vim.api.nvim_get_current_buf()
		vim.api.nvim_create_autocmd("WinClosed", {
			buffer = last_buf,
			once = true,
			callback = function()
				Tasks.fetch_all(state, deps)
			end,
		})
	else
		vim.notify("No valid task key found in the line. 💔", 1)
	end
end

--- Open the time-log UI for the selected issue.
--- @param state table
--- @param deps table
function Tasks.time_log(state, deps)
	local key = state.selected_key
	if key == "" then
		key = Tasks._extract_key()
		state.selected_key = key
	end

	if key and key ~= "" then
		deps.time.show(key, deps.jira, state.logs_persist, deps.display)
	else
		vim.notify("No valid task key found in the line. 💔", 1)
	end
end


--- Search all Jira issues via text query and show results in a scratch buffer.
--- `<cr>` opens the issue, `F` favourites it, `q` closes.
--- @param state table
--- @param deps table
function Tasks.search_issues(state, deps)
	vim.ui.input({ prompt = "Search Jira: " }, function(query)
		if not query or query == "" then return end

		local res = deps.jira.search_issues(query)
		local rows = {}
		for _, line in ipairs(vim.split(res, "\n")) do
			local raw = vim.split(line, "\t")
			local cols_arr = {}
			for _, v in ipairs(raw) do
				if v ~= "" then table.insert(cols_arr, v) end
			end
			if #cols_arr >= 4 then
				table.insert(rows, cols_arr)
			end
		end

		if #rows == 0 then
			vim.notify("No results for: " .. query, 1)
			return
		end

		-- Show results in a scratch buffer
		local buf = deps.display.new_scratch()
		vim.bo[buf].filetype = "neojira-search"
		local text, _ = deps.display.format_task_rows(rows, { sort_order = "status" })
		deps.display.put_text(buf, text)

		deps.display.nmap("<cr>", function()
			local line = vim.api.nvim_get_current_line()
			local key = line:match("([A-Z][A-Z0-9]+%-(%d+))")
			if key then
				local res = deps.jira.view_issue(key, 10)
				deps.display.put_text(buf, res)
				deps.display.nmap("q", function()
					vim.api.nvim_win_close(0, true)
				end, buf)
			end
		end, buf)

		deps.display.nmap("F", function()
			deps.favs.toggle(state.favs_persist, function()
				-- Re-query and refresh the search buffer
				Tasks.search_issues(state, deps)
			end)
		end, buf)

		deps.display.nmap("q", function()
			vim.api.nvim_win_close(0, true)
		end, buf)
	end)
end
return Tasks
