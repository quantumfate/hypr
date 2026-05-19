local M = {}

local fn = require("hypr.lib.fn")
local notify = require("hypr.lib.notify")

---Searches in all key/value pairs of a given table
---@param table any
---@return table
function M.reverse_index_lookup(table)
	return setmetatable(table, {
		__index = function(t, k)
			for key, value in pairs(t) do
				if fn.any(function(e)
					return e == k
				end, value) then
					return key
				end
			end
			notify:notify(("Reverse lookup failed for '%s'"):format(k), 3000, "ERROR")
		end,
	})
end

---Searches only in a specific field a given table
---@param table any
---@param target_key string
---@return table
function M.reverse_index_lookup_by_key(table, target_key)
	return setmetatable(table, {
		__index = function(t, k)
			for key, _ in pairs(t) do
				if fn.any(function(e)
					return e == k
				end, t[key][target_key]) then
					return key
				end
			end
			notify:notify(("Reverse lookup failed for '%s'"):format(k), 3000, "ERROR")
		end,
	})
end

return M
