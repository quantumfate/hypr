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

---@return Hosts?
function M.host_config()
	local name = M.hostname()
	return name and config.host_configs[name] or nil
end

return M
