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

---@param callable function
---@param table table
---@return boolean
function M.any_in_table(callable, table)
	for k, v in pairs(table) do
		if callable(k, v) then
			return true
		end
	end
	return false
end

---@param callable function
---@param iter table
---@return boolean
function M.all(callable, iter)
	for _, v in ipairs(iter) do
		if not callable(v) then
			return false
		end
	end
	return true
end

return M
