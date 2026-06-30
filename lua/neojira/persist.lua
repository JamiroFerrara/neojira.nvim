--- Persist — namespaced JSON key-value store backed by the Neovim data directory.
---
--- Usage:
---   local logs = Persist.new("logs")
---   logs:set("PROJ-123", 3600)
---   print(logs:get("PROJ-123"))  -- 3600
---
--- Interface: { get, set, delete, all }
local Persist = {}

local BASE = vim.fn.stdpath("data") .. "/neojira"

--- Create or open a named store.
--- @param name string — store filename (without extension)
--- @return table — { get(key) -> any|nil, set(key, val), delete(key), all() -> {key: val} }
function Persist.new(name)
	assert(type(name) == "string" and #name > 0, "persist name required")

	local filepath = BASE .. "/" .. name .. ".json"
	local cache = nil
	local dirty = false

	local function load()
		if cache ~= nil then return cache end
		-- ensure the base dir exists
		vim.fn.mkdir(BASE, "p")
		local f = io.open(filepath, "r")
		if not f then
			cache = {}
			return cache
		end
		local ok, data = pcall(vim.json.decode, f:read("*a"))
		f:close()
		if not ok or type(data) ~= "table" then
			cache = {}
		else
			cache = data
		end
		return cache
	end

	local function flush()
		if not dirty then return end
		local f = io.open(filepath, "w")
		if f then
			f:write(vim.json.encode(cache))
			f:close()
		end
		dirty = false
	end

	return {
		--- Get a value by key. Returns nil if missing.
		get = function(self, key)
			local data = load()
			return data[key]
		end,

		--- Set a key to a JSON-serializable value.
		set = function(self, key, val)
			local data = load()
			data[key] = val
			dirty = true
			flush()
		end,

		--- Delete a key from the store.
		delete = function(self, key)
			local data = load()
			data[key] = nil
			dirty = true
			flush()
		end,

		--- Return a shallow copy of the entire store as a key→value table.
		all = function(self)
			local data = load()
			local copy = {}
			for k, v in pairs(data) do
				copy[k] = v
			end
			return copy
		end,
	}
end

return Persist
