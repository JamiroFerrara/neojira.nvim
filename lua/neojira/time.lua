--- TimeTracker — worklog time tracking in an interactive scratch buffer.
local Time = {}

--- Open the time-log UI for an issue.
---
--- Renders today's logged time, preset durations, and provides keymaps for
--- logging, deleting entries, and resetting the day.
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

	local function render()
		local logs = persist:all()
		local total = 0
		for _, sec in pairs(logs) do
			total = total + sec
		end

		local lines = {
			"Log time for: " .. key,
			"",
			"Today's total: " .. display.format_seconds(total),
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
		table.insert(lines, "Press q to close")
		display.put_text(time_buf, table.concat(lines, "\n"))
	end

	render()

	local pending_time = ""
	local comment_buf = nil

	local function do_log(time_str, comment)
		jira.add_worklog(key, time_str, comment)

		local logs = persist:all()
		logs[key] = (logs[key] or 0) + display.seconds_from_str(time_str)
		persist:set(key, logs[key])
		vim.notify("Logged " .. time_str .. " on " .. key, 1)

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

		-- Remote delete via REST API
		local wl = jira.rest_get_worklogs(entry_key)
		if wl and wl.worklogs then
			local today = os.date("%Y-%m-%d")
			for _, entry in ipairs(wl.worklogs) do
				local started = (entry.started or ""):sub(1, 10)
				if started == today and entry.id then
					jira.rest_delete_worklog(entry_key, entry.id)
				end
			end
		end

		-- Local removal
		persist:delete(entry_key)
		render()
	end

	local function reset_today()
		vim.ui.input({ prompt = "Delete all today's worklogs from server too? (y/N): " }, function(answer)
			if answer ~= "y" and answer ~= "Y" then return end

			-- Clear local store
			local logs = persist:all()
			for k in pairs(logs) do
				persist:delete(k)
			end

			-- Delete all today's worklogs from server
			local data = jira.rest_search("worklogDate >= startOfDay()")
			if data and data.issues then
				for _, issue in ipairs(data.issues) do
					local wl = jira.rest_get_worklogs(issue.key)
					if wl and wl.worklogs then
						local today = os.date("%Y-%m-%d")
						for _, entry in ipairs(wl.worklogs) do
							local started = (entry.started or ""):sub(1, 10)
							if started == today and entry.id then
								jira.rest_delete_worklog(issue.key, entry.id)
							end
						end
					end
				end
			end

			vim.notify("Today's time reset", 1)
			render()
		end)
	end

	display.nmap("R", reset_today, time_buf)
	display.nmap("d", delete_entry, time_buf)
	display.nmap("q", function()
		vim.api.nvim_win_close(0, true)
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

	local logs = persist:all()
	logs[key] = (logs[key] or 0) + hours * 3600
	persist:set(key, logs[key])

	vim.notify("Logged " .. time_str .. " on " .. key, 1)
	if on_log then on_log() end
end

return Time
