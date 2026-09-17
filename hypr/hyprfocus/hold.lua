-- Parking windows a mode does not admit, and giving them back.
--
-- Holding is what makes withdrawing a workspace safe. Disabling a workspace
-- that still holds windows leaves them somewhere the user cannot reach, which
-- from their side is indistinguishable from having lost them — so the windows
-- move first, the workspace is withdrawn second, and the reverse on the way
-- back.
--
-- A held window is alive. Nothing is saved and nothing is closed: this buys
-- attention, not capacity. A resource whose cost is the reason it is being
-- revoked is retired instead, and retiring is not this module's business.
--
-- Where they go is a special workspace, which is never declared and so can
-- never be admitted or withdrawn itself. That matters: a holding place that a
-- mode could withdraw would strand exactly the windows it exists to protect.
local store = require("hypr.lib.store")
local shelf = require("hypr.lib.shelf")

local M = {}

---Shelves are runtime config, not this module's; a hold spec that never sets
---`_G.config` sees none, which is the same as a desk with no shelves at all.
---@return Shelf[]
local function shelves()
  return (rawget(_G, "config") or {}).shelves or {}
end

-- Windows go here. Special workspaces carry negative ids and are never a
-- scene's home, so nothing else in the engine will try to arrange it.
local HELD = "special:hyprfocus-held"

-- Where held windows came from, so they go back where they were rather than
-- reappearing somewhere plausible. Persisted because a shell restart must not
-- turn a held window into a lost one.
local RECORD = "hyprfocus-held"

---@return table<string, string> address -> the workspace it came from
local function origins()
  local ok, handle = pcall(store.define, RECORD)
  if not ok then
    return {}
  end
  local data = handle:get("windows")
  return type(data) == "table" and data or {}
end

---@param windows table<string, string>
local function remember(windows)
  local ok, handle = pcall(store.define, RECORD)
  if ok then
    pcall(function()
      handle:set({ windows = windows })
    end)
  end
end

---@param address string
---@param workspace string
local function move(address, workspace)
  hl.dispatch(hl.dsp.window.move({
    window = "address:" .. address,
    workspace = workspace,
    -- The user did not ask to go anywhere. A following move drags them to
    -- wherever the window landed, which on a mode change means being thrown
    -- across the desk once per window.
    follow = false,
  }))
end

---Park every window standing on `workspace`.
---@param workspace string the workspace's name
---@return integer how many windows were parked
function M.hold(workspace)
  local recorded = origins()
  local parked = 0
  for _, w in ipairs(hl.get_windows() or {}) do
    local ws = w.workspace
    if ws and ws.name == workspace and w.address and not recorded[w.address] and not shelf.exempt(w, shelves()) then
      recorded[w.address] = workspace
      move(w.address, HELD)
      parked = parked + 1
    end
  end
  if parked > 0 then
    remember(recorded)
  end
  return parked
end

---Give back every window held from `workspace`.
---
---Windows that died while held are dropped from the record rather than
---restored: addresses are reused, and putting a window back by an address that
---now belongs to something else would move a stranger.
---@param workspace string
---@return integer how many windows came back
function M.restore(workspace)
  local recorded = origins()
  local live = {}
  for _, w in ipairs(hl.get_windows() or {}) do
    if w.address then
      live[w.address] = w
    end
  end

  -- Sorted, so a restore moves windows in the same order every time and the
  -- decision log reads the same twice.
  local addresses = {}
  for address in pairs(recorded) do
    addresses[#addresses + 1] = address
  end
  table.sort(addresses)

  local returned, remaining = 0, {}
  for _, address in ipairs(addresses) do
    local origin = recorded[address]
    if origin ~= workspace then
      remaining[address] = origin
    elseif live[address] and not shelf.exempt(live[address], shelves()) then
      move(address, "name:" .. origin)
      returned = returned + 1
    end
  end
  remember(remaining)
  return returned
end

---Every workspace that currently has windows held from it.
---@return table<string, true>
function M.workspaces()
  local out = {}
  for _, origin in pairs(origins()) do
    out[origin] = true
  end
  return out
end

---@param address string
---@return string? the workspace this window was held from
function M.origin(address)
  return origins()[address]
end

---Drop every record without moving anything. For tests, and for recovering
---from a record that no longer describes reality.
function M.forget()
  remember({})
end

return M
