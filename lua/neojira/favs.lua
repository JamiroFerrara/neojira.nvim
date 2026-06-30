--- Favs — favourite/pin issue management.
local Favs = {}

--- Toggle favourite status for an issue key extracted from the current line.
--- Calls persist:set() / persist:delete() and notifies the user.
--- @param persist table — Persist store (expected to have get/set/delete/all)
--- @param on_change function — callback after toggling (e.g. to refresh the list)
function Favs.toggle(persist, on_change)
	local line = vim.api.nvim_get_current_line()
	local key = line:match("([A-Z][A-Z0-9]+%-(%d+))")
	if not key then return end

	local favs = persist:all()
	if favs[key] then
		persist:delete(key)
		vim.notify("Unpinned " .. key, 1)
	else
		persist:set(key, true)
		vim.notify("Pinned " .. key, 1)
	end

	if on_change then on_change() end
end

--- Get the set of favourited keys as a `{key -> true}` lookup table.
--- @param persist table
--- @return table
function Favs.get_all(persist)
	return persist:all()
end

return Favs
