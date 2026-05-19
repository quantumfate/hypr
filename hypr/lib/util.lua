local M = {}

---@return string?
function M.hostname()
	local f = io.popen("hostname")
	if not f then
		return nil
	end
	local name = f:read("*l")
	f:close()
	return name
end

return M
