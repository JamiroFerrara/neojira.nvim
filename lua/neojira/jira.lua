--- JiraDataSource — all Jira communication behind a small interface.
---
--- Wraps both the `jira` CLI and direct REST API (curl) calls.
--- Accepts dependencies so tests can swap in a fake adapter.
local Jira = {}

--- Create a new JiraDataSource instance.
--- @param config table — { browser, company_name, email? }
--- @return table — JiraDataSource interface
function Jira.new(config)
	assert(config, "config required for Jira.new")
	local browser = config.browser
	local company = config.company_name
	-- Backward-compatible email fallback
	local email = config.email or "j.ferrara@novigo-consulting.it"

	--- Compute the Basic auth header value from JIRA_API_TOKEN.
	--- @return string|nil — base64-encoded "email:token" or nil when token is unset
	local function basic_auth()
		local token = os.getenv("JIRA_API_TOKEN")
		if not token then return nil end
		return vim.trim(vim.fn.system("echo -n '" .. email .. ":" .. token .. "' | base64 -w0"))
	end

	--- Fetch issues matching a JQL query.
	--- @param jql string
	--- @param columns string — comma-separated column names
	--- @param status_filter string — e.g. "-s~Chiuso -s~Risolti" or ""
	--- @return string — raw tab-separated output
	local function list_issues(jql, columns, status_filter)
		status_filter = status_filter or ""
		local cmd = "jira issue list --plain --no-headers --columns " .. columns
			.. " " .. status_filter .. " --jql '" .. jql .. "'"
		return vim.fn.system(cmd)
	end

	--- View a single issue with comments.
	--- @param key string — e.g. "PROJ-123"
	--- @param ncomments integer — number of comments to show (default 10)
	--- @return string — rendered issue text
	local function view_issue(key, ncomments)
		ncomments = ncomments or 10
		return vim.fn.system("jira issue view --plain --comments=" .. ncomments .. " " .. key)
	end

	--- Open an interactive terminal running `jira issue move`.
	local function move_issue(key)
		vim.api.nvim_command("terminal jira issue move " .. key)
	end

	--- Write comment text to a temp file and open a terminal that pipes it into `jira issue comment add`.
	--- @param key string
	--- @param text string
	local function add_comment(key, text)
		local temp_file = "/tmp/jira_comment.txt"
		local f = io.open(temp_file, "w")
		if f then f:write(text); f:close() end
		vim.api.nvim_command("terminal jira issue comment add " .. key .. " < " .. temp_file)
	end

	--- Add a worklog entry with optional comment.
	--- @param key string
	--- @param time_str string — e.g. "2h 30m"
	--- @param comment string|nil — optional comment text
	--- @return string — command output
	local function add_worklog(key, time_str, comment)
		local cmd = 'jira issue worklog add ' .. key .. ' "' .. time_str .. '"'
		if comment and comment ~= "" then
			local f = io.open("/tmp/neojira_comment.txt", "w")
			if f then f:write(comment); f:close() end
			cmd = cmd .. " --comment \"$(cat /tmp/neojira_comment.txt)\""
		end
		return vim.fn.system(cmd .. " --no-input")
	end

	--- Quick-log time without prompting.
	--- @param key string
	--- @param time_str string — e.g. "1h"
	--- @return string — command output
	local function quick_add_worklog(key, time_str)
		return vim.fn.system('jira issue worklog add ' .. key .. ' "' .. time_str .. '" --no-input')
	end

	--- Open an issue in the default browser.
	--- @param key string
	local function open_in_browser(key)
		vim.fn.system(browser .. " https://" .. company .. ".atlassian.net/browse/" .. key)
	end

	--- Fetch worklogs for an issue via the Jira REST API.
	--- @param key string
	--- @return table|nil — parsed JSON response with `.worklogs` array, or nil
	local function rest_get_worklogs(key)
		local auth = basic_auth()
		if not auth then return nil end
		local url = "https://" .. company .. ".atlassian.net/rest/api/3/issue/" .. key .. "/worklog"
		local res = vim.fn.system("curl -s --http1.1 -H 'Authorization: Basic " .. auth .. "' '" .. url .. "'")
		local ok, data = pcall(vim.json.decode, res)
		if ok and type(data) == "table" then return data end
		return nil
	end

	--- Delete a worklog entry via the Jira REST API.
	--- @param key string
	--- @param worklog_id string|integer
	--- @return boolean — true if the request was attempted
	local function rest_delete_worklog(key, worklog_id)
		local auth = basic_auth()
		if not auth then return false end
		local url = "https://" .. company .. ".atlassian.net/rest/api/3/issue/" .. key .. "/worklog/" .. worklog_id
		vim.fn.system("curl -s --http1.1 -X DELETE -H 'Authorization: Basic " .. auth .. "' '" .. url .. "'")
		return true
	end

	--- Search issues via the Jira REST API JQL endpoint.
	--- @param jql string
	--- @return table|nil — parsed JSON with `.issues` array, or nil
	local function rest_search(jql)
		local auth = basic_auth()
		if not auth then return nil end
		local url = "https://" .. company .. ".atlassian.net/rest/api/3/search/jql"
		local payload = '{"jql":"' .. jql .. '","fields":["key"],"maxResults":30}'
		local cmd = "curl -s --http1.1 -X POST -H 'Authorization: Basic " .. auth
			.. "' -H 'Content-Type: application/json' -d '" .. payload .. "' '" .. url .. "'"
		local res = vim.fn.system(cmd)
		local ok, data = pcall(vim.json.decode, res)
		if ok and type(data) == "table" then return data end
		return nil
	end

	return {
		list_issues = list_issues,
		view_issue = view_issue,
		move_issue = move_issue,
		add_comment = add_comment,
		add_worklog = add_worklog,
		quick_add_worklog = quick_add_worklog,
		open_in_browser = open_in_browser,
		rest_get_worklogs = rest_get_worklogs,
		rest_delete_worklog = rest_delete_worklog,
		rest_search = rest_search,
	}
end

return Jira
