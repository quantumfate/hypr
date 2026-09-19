-- Workspaces, held by name so a mode can admit or withhold them.
--
-- Workspaces stop being fixed at config load and become a function of the
-- active mode. `hl.workspace_rule` returns a handle carrying `set_enabled`, so
-- a workspace can be withdrawn and brought back with no reload — which is what
-- makes "this mode has four workspaces" a thing the desk can actually do
-- rather than a thing it merely displays.
--
-- Unlike binding trees, there is a single place that creates workspace rules,
-- so handles are recorded there directly rather than by wrapping the API.
--
-- Withdrawing a workspace is not the same as hiding its windows. This module
-- only governs whether the workspace is reachable; what happens to the windows
-- standing on it is the reconciler's business, and a workspace withdrawn with
-- windows still on it would strand them somewhere the user cannot reach. The
-- guard below refuses that outright rather than trusting callers to order the
-- two correctly.
local M = {}

-- Workspace name -> its rule handle.
---@type table<string, HL.WorkspaceRule>
local rules = {}

---Record a workspace rule under the name a declaration would use for it.
---
---A workspace the host gave no `default_name` is not recorded, and so is never
---withheld: nothing could name it to admit it back.
---@param name string? the rule's `default_name`
---@param handle HL.WorkspaceRule?
function M.record(name, handle)
  if name and handle then
    rules[name] = handle
  end
end

---@return string[] every named workspace, sorted
function M.names()
  local out = {}
  for name in pairs(rules) do
    out[#out + 1] = name
  end
  table.sort(out)
  return out
end

---@param name string
---@return boolean
function M.known(name)
  return rules[name] ~= nil
end

---Enable exactly the named workspaces and disable the rest.
---
---`occupied` names workspaces that still hold windows. They are never
---withdrawn: a workspace disabled while its windows stand on it leaves them
---somewhere the user cannot reach, which is indistinguishable from having lost
---them. The caller holds or moves the windows first, then asks again.
---`main` is enabled LAST. Enabling a persistent workspace brings it up on its
---output, and the last one to come up there is the one left showing -- so the
---plain sorted order quietly handed the desk to whichever admitted workspace
---sorted last per monitor (`proton` beat `code` on the primary, alphabetically,
---every reload). The mode already declares which scene it considers main; this
---is what makes that declaration decide the question instead of the alphabet.
---@param admitted string[]
---@param occupied table<string, true>? workspaces that still hold windows
---@param main string? the running mode's declared main scene, enabled last
---@return string[] withdrawn, string[] refused because they were occupied
function M.admit(admitted, occupied, main)
  occupied = occupied or {}
  local wanted = {}
  for _, name in ipairs(admitted or {}) do
    wanted[name] = true
  end

  local order = {}
  for _, name in ipairs(M.names()) do
    if name ~= main then
      order[#order + 1] = name
    end
  end
  if main and rules[main] then
    order[#order + 1] = main
  end

  local withdrawn, refused = {}, {}
  for _, name in ipairs(order) do
    local on = wanted[name] == true
    if not on and occupied[name] then
      on = true
      refused[#refused + 1] = name
    elseif not on then
      withdrawn[#withdrawn + 1] = name
    end
    pcall(function()
      rules[name]:set_enabled(on)
    end)
  end
  return withdrawn, refused
end

---Which admitted workspaces currently hold tiled windows, so a caller can pass
---`occupied` without walking the window list itself.
---@return table<string, true>
function M.occupied()
  local out = {}
  for _, w in ipairs(hl.get_windows() or {}) do
    local ws = w.workspace
    if ws and ws.name then
      out[ws.name] = true
    end
  end
  return out
end

---Drop the recorded handles. For tests; a config reload rebuilds them.
function M.reset()
  rules = {}
end

return M
