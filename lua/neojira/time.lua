--- TimeTracker — worklog time tracking in an interactive scratch buffer.
local Time = {}

--- Build the persist store key for a given date and issue key.
--- @param date string — "YYYY-MM-DD"
--- @param key string — e.g. "PROJ-123"
--- @return string
local function store_key(date, key)
	return date .. ":" .. key
end

--- Extract (date, issue_key) from a store key.
--- @param sk string — e.g. "2026-06-30:PROJ-123"
--- @return string, string
local function parse_store_key(sk)
	return sk:match("(%d+%-%d+%-%d+):(.+)")
end

--- Get today's date string.
--- @return string
local function today()
	return os.date("%Y-%m-%d")
end

--- Format a date string for display.
--- @param date string
--- @return string
local function display_date(date)
	if date == today() then return date .. " (today)" end
	local yesterday = os.date("%Y-%m-%d", os.time() - 86400)
	if date == yesterday then return date .. " (yesterday)" end
	return date
end

--- Shift a date by N days.
--- @param date string — "YYYY-MM-DD"
--- @param delta integer
--- @return string
local function shift_date(date, delta)
	local t = os.time({ year = tonumber(date:sub(1,4)), month = tonumber(date:sub(6,2)), day = tonumber(date:sub(9,10)) })
	return os.date("%Y-%m-%d", t + delta * 86400)
end

--- Open the time-log UI for an issue.
---
--- Renders the selected day's logged time, preset durations, and provides keymaps for
--- logging, deleting entries, and resetting the day. H/L navigate between days.
--- @param key string — issue key
--- @param jira table — JiraDataSource instance
--- @param persist table — Persist store for "logs"
--- @param display table — Display module
function Time.show(key, jira, persist, display)
	if not key then
		vim.notify("No valid task key found in the line. 💔", 1)
		return
	end

	display.split(true)
	local time_buf = display.new_scratch()
	vim.bo[time_buf].filetype = "neojira-time"

	local current_date = today()

	local function logs_for_date(date)
		local prefix = date .. ":"
		local all = persist:all()
		local result = {}
		for k, v in pairs(all) do
			if k:sub(1, #prefix) == prefix then
				local _, issue = parse_store_key(k)
				if issue then
					result[issue] = v
				end
			end
		end
		return result
	end

	local function render()
		local logs = logs_for_date(current_date)
		local total = 0
		for _, sec in pairs(logs) do
			total = total + sec
		end

		local lines = {
			"Log time for: " .. key,
			"",
			display_date(current_date) .. " — total: " .. display.format_seconds(total),
			"",
		}

		local sorted_keys = {}
		for k in pairs(logs) do
			table.insert(sorted_keys, k)
		end
		table.sort(sorted_keys)

		for _, k in ipairs(sorted_keys) do
			table.insert(lines, "  " .. k .. "  " .. display.format_seconds(logs[k]))
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
		table.insert(lines, "H/L: change day  R: reset day  d: delete entry  q: close")
		display.put_text(time_buf, table.concat(lines, "\n"))
	end

	render()

	local pending_time = ""
	local comment_buf = nil

	local function do_log(time_str, comment)
		jira.add_worklog(key, time_str, comment)

		local sk = store_key(current_date, key)
		local all = persist:all()
		all[sk] = (all[sk] or 0) + display.seconds_from_str(time_str)
		persist:set(sk, all[sk])
		vim.notify("Logged " .. time_str .. " on " .. key .. " (" .. current_date .. ")", 1)

		-- Close comment window
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

		display.split(true)
		comment_buf = display.new_scratch()
		vim.bo[comment_buf].filetype = "neojira-comment"
		display.put_text(comment_buf, "Comment for " .. key .. " " .. time_str .. " (empty to skip):\n\n")
		vim.api.nvim_win_set_cursor(0, { 3, 0 })
		vim.cmd("startinsert")

		local function submit_comment()
			local lines = vim.api.nvim_buf_get_lines(comment_buf, 0, -1, false)
			local raw = table.concat(lines, "\n")
			local comment = raw:gsub("^Comment for .+ %(empty to skip%):\n\n", ""):gsub("^\n*", ""):gsub("\n*$", "")
			do_log(pending_time, comment)
		end

		display.nmap("<cr>", submit_comment, comment_buf)
		display.imap("<cr>", submit_comment, comment_buf)
		display.nmap("q", function()
			do_log(pending_time, "")
		end, comment_buf)
	end

	local function log_time()
		local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
		local line_content = vim.api.nvim_buf_get_lines(time_buf, cursor_line - 1, cursor_line, false)[1]
		local time_str = line_content:match("^%s+(.+)")
		if not time_str or time_str == "" then return end
		start_comment(time_str)
	end

	display.nmap("<cr>", log_time, time_buf)
	for i = 1, 8 do
		display.nmap(tostring(i), function()
			start_comment(i .. "h")
		end, time_buf)
	end

	local function delete_entry()
		local line = vim.api.nvim_get_current_line()
		local entry_key = line:match("^%s+([A-Z][A-Z0-9]+%-%d+)")
		if not entry_key then return end

		-- Remote delete via REST API (only for today's entries)
		if current_date == today() then
			local wl = jira.rest_get_worklogs(entry_key)
			if wl and wl.worklogs then
				for _, entry in ipairs(wl.worklogs) do
					local started = (entry.started or ""):sub(1, 10)
					if started == current_date and entry.id then
						jira.rest_delete_worklog(entry_key, entry.id)
					end
				end
			end
		end

		-- Local removal for the current date
		persist:delete(store_key(current_date, entry_key))
		render()
	end

	local function reset_day()
		vim.ui.input({ prompt = "Delete all " .. current_date .. " worklogs from server too? (y/N): " }, function(answer)
			if answer ~= "y" and answer ~= "Y" then
				-- Just clear local entries for this date
				local prefix = current_date .. ":"
				local all = persist:all()
				for k in pairs(all) do
					if k:sub(1, #prefix) == prefix then
						persist:delete(k)
					end
				end
				vim.notify(current_date .. " time reset locally", 1)
				render()
				return
			end

			-- Clear local entries for this date
			local prefix = current_date .. ":"
			local all = persist:all()
			for k in pairs(all) do
				if k:sub(1, #prefix) == prefix then
					persist:delete(k)
				end
			end

			-- Delete from server for this date
			local data = jira.rest_search("worklogDate = \"" .. current_date .. "\"")
			if data and data.issues then
				for _, issue in ipairs(data.issues) do
					local wl = jira.rest_get_worklogs(issue.key)
					if wl and wl.worklogs then
						for _, entry in ipairs(wl.worklogs) do
							local started = (entry.started or ""):sub(1, 10)
							if started == current_date and entry.id then
								jira.rest_delete_worklog(issue.key, entry.id)
							end
						end
					end
				end
			end

			vim.notify(current_date .. " time reset", 1)
			render()
		end)
	end

	display.nmap("R", reset_day, time_buf)
	display.nmap("d", delete_entry, time_buf)
	display.nmap("q", function()
		vim.api.nvim_win_close(0, true)
	end, time_buf)
	display.nmap("H", function()
		current_date = shift_date(current_date, -1)
		render()
	end, time_buf)
	display.nmap("L", function()
		current_date = shift_date(current_date, 1)
		render()
	end, time_buf)
end

--- Quick-log N hours without opening the time UI.
--- @param key string — issue key extracted from current line
--- @param hours integer
--- @param jira table — JiraDataSource instance
--- @param persist table — Persist store for "logs"
--- @param on_log function — callback after logging (e.g. to refresh the task list)
function Time.quick_log(key, hours, jira, persist, on_log)
	if not key then
		vim.notify("No valid task key found in the line. 💔", 1)
		return
	end

	local time_str = hours .. "h"
	jira.quick_add_worklog(key, time_str)

	local date = today()
	local sk = store_key(date, key)
	local all = persist:all()
	all[sk] = (all[sk] or 0) + hours * 3600
	persist:set(sk, all[sk])

	vim.notify("Logged " .. time_str .. " on " .. key, 1)
	if on_log then on_log() end
end

return Time
