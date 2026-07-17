---@class Dofus.Common
---@field default_team string
---@field selected string currently selected team key (from team.json)
---@field characters table<string, string[]> team key -> ordered names
---@field title_prefix string
---
--- Single source of truth for the Dofus team is a shared JSON store, also read
--- and written by the Quickshell UI (~/Projects/github/quantumfate/quickshell)
--- and fed to dofus_swap.py:
---
---   $XDG_STATE_HOME/dofus/team.json  <->  hypr/lib/store  <->  Quickshell UI
---
--- List ORDER is meaningful (turn order, F1..F8, launch order, swap args).
--- The store keeps a decoded copy in RAM and refreshes it whenever the file
--- changes, so edits made in the UI (or by any script) are picked up on the
--- next access without a config reload.
local Store = require("hypr.lib.store")

local M = {}

M.default_team = "pioneer"

local store = Store.define("dofus/team")

---Currently selected team's character list (turn order = list order).
---@return string[]
function M.team()
  local sel = store:get("selected") or M.default_team
  return store:get("teams", sel) or {}
end

---Select the active team, persisting it back to the store (no-op if unknown).
---Writing the file lets the Quickshell UI react to the change too.
---@param name string team key
function M.select(name)
  if not store:get("teams", name) then
    return
  end
  store:set({ selected = name })
end

-- Field access (M.selected / M.title_prefix / M.characters) reads live from the
-- store; the functions above take priority over this fallback.
setmetatable(M, {
  __index = function(_, k)
    if k == "selected" then
      return store:get("selected") or M.default_team
    elseif k == "title_prefix" then
      return store:get("title_prefix") or "Dofus "
    elseif k == "characters" then
      return store:get("teams") or {}
    end
    return nil
  end,
})

return M
