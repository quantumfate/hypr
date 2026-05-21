local M = {}

---comment
---@param iter table<any, any>[]
---@return table<any,any>
function M.flatten(iter)
	local out = {}
	for _, t in ipairs(iter) do
		for k, v in pairs(t) do
			out[k] = v
		end
	end
	return out
end
return M
