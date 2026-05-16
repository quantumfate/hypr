local M = {}

---@param callable function
---@param iter table
---@return boolean
function M.any(callable, iter)
	for _, v in ipairs(iter) do
		if callable(v) then
			return true
		end
	end
	return false
end

return M
