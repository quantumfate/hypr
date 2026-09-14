-- The compositor's state, flattened (LEO-245).
--
-- The only reader of `hl.get_*` in the engine. Everything past this point
-- works on plain tables, which is what lets the model be tested with fixtures
-- instead of a running Hyprland.
local M = {}

---HL.Group.members is a bare window when the group holds exactly one,
---otherwise an array — normalize to an array (the shape team.lua also reads).
---@param group HL.Group?
---@return HL.Window[]
local function members(group)
  local list = group and group.members
  if not list then
    return {}
  end
  if list.title then
    return { list }
  end
  return list
end

---A key shared by every member of one group and by no other group. The lowest
---member address serves: group objects are not comparable across reads, and
---the address set is exactly what "same group" means.
---@param w HL.Window
---@return string?
local function group_key(w)
  local lowest
  for _, member in ipairs(members(w.group)) do
    if member.address and (not lowest or member.address < lowest) then
      lowest = member.address
    end
  end
  return lowest
end

---@return Scene.Snapshot
function M.read()
  local active = hl.get_active_workspace()
  local windows = {}
  for _, w in ipairs(hl.get_windows() or {}) do
    local ws = w.workspace
    if w.address and w.at and w.size then
      windows[#windows + 1] = {
        address = w.address,
        class = w.class,
        workspace = ws and ws.name or nil,
        workspace_id = ws and tonumber(tostring(ws.id)) or nil,
        floating = w.floating == true,
        group = group_key(w),
        x = w.at.x,
        y = w.at.y,
        w = w.size.x,
        h = w.size.y,
      }
    end
  end
  return { active = active and active.name or nil, windows = windows }
end

return M
