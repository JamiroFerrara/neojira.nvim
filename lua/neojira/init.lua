--- neojira.nvim — Jira integration for Neovim.
---
--- Entry point. Wires all feature modules together, manages state, and
--- exposes the public API: `setup(config)` and `run()`.
local M = {}

-- Dependencies
local Display = require("neojira.display")
local Jira = require("neojira.jira")
local Persist = require("neojira.persist")
local Favs = require("neojira.favs")
local Comments = require("neojira.comments")
local Time = require("neojira.time")
local Tasks = require("neojira.tasks")

-- Module-level state (mutable, shared across closures)
local state = {
	selected_key = "",
	task_list = "",
	show_all_assignees = false,
	show_all_statuses = false,
	sort_order = "status",
	buf_tasks = nil,
	username = "",
	fav_ns = nil,
}

-- Dependencies bag (initialised in setup(), used by run())
local deps
local logs_persist
local favs_persist

--- Setup the plugin.
--- @param config table — { username, browser, company_name, email? }
function M.setup(config)
	state.username = config.username

	-- Initialise persistence
	logs_persist = Persist.new("logs")
	favs_persist = Persist.new("favs")

	-- Dependencies bag (injected so feature modules never import globals)
	deps = {
		jira = Jira.new(config),
		display = Display,
		persist = Persist,
		favs = Favs,
		comments = Comments,
		time = Time,
	}

	-- Create highlight group for favourite rows
	vim.api.nvim_set_hl(0, "NeojiraFav", { fg = "#89b4fa", bold = true })
	state.fav_ns = vim.api.nvim_create_namespace("neojira_fav")

	-- Extend state with persistence handles
	state.logs_persist = logs_persist
	state.favs_persist = favs_persist

	-- Create the user command
	vim.api.nvim_create_user_command("Neojira", function()
		M.run()
	end, {})
end

--- Open the Jira task list buffer.
--- @param deps_override table|nil — for testing or custom wiring
function M.run(deps_override)
	deps = deps_override or deps
	if not deps then
		vim.notify("neojira: call setup(config) first", 1)
		return
	end

	state.selected_key = ""
	state.task_list = ""
	state.buf_tasks = Display.new_scratch()

	Tasks.fetch_all(state, deps)
	Tasks.register_keymaps(state, deps)
end

return M
