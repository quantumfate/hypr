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

---Current host config. Resolved once in hyprland.lua; prefer `config.host`.
---@return Hosts
function M.host_config()
  return config.host
end

return M
