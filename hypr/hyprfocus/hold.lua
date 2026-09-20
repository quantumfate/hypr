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
local drawer = require("hypr.lib.drawer")

local M = {}

---Drawers are declared data, read live from the hyprfocus store; a hold spec
---whose store stub carries no declaration sees none, the same as a desk with
---no drawers at all.
---@return Drawer[]
local function drawers()
  return drawer.load()
end

-- Windows go here. Special workspaces carry negative ids and are never a
-- scene's home, so nothing else in the engine will try to arrange it.
local HELD = "special:hyprfocus-held"

-- Where held windows came from, so they go back where they were rather than
-- reappearing somewhere plausible. Persisted because a shell restart must not
-- turn a held window into a lost one.
local RECORD = "hyprfocus-held"

-- The record lives in memory for the life of the config: the compositor runs
-- one Lua state, so every hold and restore within an apply sees the previous
-- one's writes. The store is only a mirror that survives a restart; reading it
-- back on every call raced its own mtime cache and dropped entries between two
-- holds of the same apply.
---@type table<string, string>?
local record

---@return table<string, string> address -> the workspace it came from
local function origins()
  if record then
    return record
  end
  record = {}
  local ok, handle = pcall(store.define, RECORD)
  if ok then
    local data = handle:get("windows")
    if type(data) == "table" then
      for address, origin in pairs(data) do
        record[address] = origin
      end
    end
  end
  return record
end

---@param windows table<string, string>
local function remember(windows)
  record = windows
  local ok, handle = pcall(store.define, RECORD)
  if ok then
    pcall(function()
      handle:set({ windows = windows })
    end)
  end
end

---Forget the in-memory record so the next read comes from the store. For
---specs; a config reload starts a fresh Lua state anyway.
function M.reset()
  record = nil
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

---Drop records for addresses no live window carries. Addresses are reused,
---so a dead entry left behind would later claim a stranger.
---@param recorded table<string, string>
---@param live table<string, table>
---@return table<string, string>
local function prune(recorded, live)
  local out = {}
  for address, origin in pairs(recorded) do
    if live[address] then
      out[address] = origin
    end
  end
  return out
end

---@return table<string, table> address -> live window
local function live_windows()
  local live = {}
  for _, w in ipairs(hl.get_windows() or {}) do
    if w.address then
      live[w.address] = w
    end
  end
  return live
end

---Park every window standing on `workspace`.
---
---A window standing on a named workspace is not held, whatever the record
---says: an entry for its address is stale (a reused address, or a record
---written by an interrupted apply) and is overwritten. Skipping such a window
---used to leave it on a workspace the caller then withdrew, which stranded it.
---@param workspace string the workspace's name
---@return integer parked, string[] addresses moved
function M.hold(workspace)
  local live = live_windows()
  local recorded = prune(origins(), live)
  local moved = {}
  for _, w in ipairs(hl.get_windows() or {}) do
    local ws = w.workspace
    if ws and ws.name == workspace and w.address and not drawer.exempt(w, drawers()) then
      recorded[w.address] = workspace
      move(w.address, HELD)
      moved[#moved + 1] = w.address
    end
  end
  remember(recorded)
  return #moved, moved
end

---Give back every window held from `workspace`.
---
---Windows that died while held are dropped from the record rather than
---restored: addresses are reused, and putting a window back by an address that
---now belongs to something else would move a stranger.
---@param workspace string
---@return integer returned, string[] addresses moved back
function M.restore(workspace)
  local live = live_windows()
  local recorded = origins()

  -- Sorted, so a restore moves windows in the same order every time and the
  -- decision log reads the same twice.
  local addresses = {}
  for address in pairs(recorded) do
    addresses[#addresses + 1] = address
  end
  table.sort(addresses)

  local moved, remaining = {}, {}
  for _, address in ipairs(addresses) do
    local origin = recorded[address]
    if origin ~= workspace then
      if live[address] then
        remaining[address] = origin
      end
    elseif live[address] and not drawer.exempt(live[address], drawers()) then
      move(address, "name:" .. origin)
      moved[#moved + 1] = address
    end
  end
  remember(remaining)
  return #moved, moved
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

-- The holding place's workspace name, for callers that check where a window
-- stands.
M.HELD = HELD

---Where each window will stand once the moves an apply dispatched land. A
---move is dispatched, not performed, so reading the compositor right after an
---apply returns the desk as it was; this overlays the moves instead.
---@param windows table[] `hl.get_windows()`
---@param moves table<string, string> address -> workspace name it was sent to
---@return { address: string, class: string?, workspace: string? }[]
function M.project(windows, moves)
  local out = {}
  for _, w in ipairs(windows or {}) do
    if w.address then
      out[#out + 1] = {
        address = w.address,
        class = w.class,
        workspace = moves[w.address] or (w.workspace and w.workspace.name),
      }
    end
  end
  return out
end

---The reachability invariant, checked after every mode apply. A window is
---reachable when it stands on an admitted workspace, on a shelf
---(a shelf's special workspace), on any other special or unmanaged workspace, or in the
---holding place with a recorded origin the active mode does not admit (a
---later mode brings it back). Everything else is returned with a token:
---
---  * `withdrawn` — on a managed workspace the mode withdrew
---  * `no_origin` — held with no record, so no mode can ever restore it
---  * `not_restored` — held from a workspace the active mode admits
---
---Pure: the caller hands in the projected windows and the record.
---@param windows { address: string, class: string?, workspace: string? }[]
---@param admitted table<string, true>
---@param known table<string, true> managed workspace names (the registry)
---@param recorded table<string, string> address -> origin
---@return { address: string, class: string?, workspace: string?, reason: string }[]
function M.unreachable(windows, admitted, known, recorded)
  local out = {}
  for _, w in ipairs(windows or {}) do
    local ws = w.workspace
    local reason
    if ws == HELD then
      local origin = recorded[w.address]
      if not origin then
        reason = "no_origin"
      elseif admitted[origin] then
        reason = "not_restored"
      end
    elseif ws and known[ws] and not admitted[ws] then
      reason = "withdrawn"
    end
    if reason then
      out[#out + 1] = { address = w.address, class = w.class, workspace = ws, reason = reason }
    end
  end
  table.sort(out, function(a, b)
    return a.address < b.address
  end)
  return out
end

---The record as it stands, for the invariant check.
---@return table<string, string>
function M.record()
  return origins()
end

---Give a held window an origin it lost.
---
---A window in the holding place with no record is one no mode can restore
---(`unreachable`'s `no_origin`): the record write that should have named its
---origin never landed, or a reload started a fresh state before it did. The
---window is alive and where it belongs — only the note saying where it came
---from is missing — so writing that note is the repair, and the next mode
---admitting `workspace` gives it back. Adopting is preferred over evicting it
---to whatever the primary happens to show: a class its scene claims has a
---home, and the holding place is the right place to wait for it.
---@param address string
---@param workspace string the workspace it should be given back to
function M.adopt(address, workspace)
  if not address or not workspace then
    return
  end
  local recorded = origins()
  recorded[address] = workspace
  remember(recorded)
end

---Drop every record without moving anything. For tests, and for recovering
---from a record that no longer describes reality.
function M.forget()
  remember({})
end

return M
