-- Which windows a scene owns (LEO-245).
--
-- Ownership is earned by *mapping into* the scene, never by matching its
-- classes. The distinction is the whole point: a terminal you deliberately
-- moved to another workspace matches the `code` scene's classes exactly, and
-- must not be dragged back. Only what the scene actually received can drift.
local spec_lib = require("hypr.scene.spec")

local M = {}

---@type table<string, string> window address -> scene name
local owner = {}

---Record `w` as the scene's, if it is on a scene's workspace and matches one
---of its blocks.
---@param specs table<string, Scene.Spec>
---@param w HL.Window?
function M.claim(specs, w)
  local ws = w and w.workspace
  local spec = ws and specs[ws.name]
  if spec and spec_lib.block_for(spec, w.class) then
    owner[w.address] = spec.name
  end
end

---@param address string?
function M.forget(address)
  if address then
    owner[address] = nil
  end
end

---@param name string
---@return table<string, true>
function M.owned(name)
  local out = {}
  for address, scene in pairs(owner) do
    if scene == name then
      out[address] = true
    end
  end
  return out
end

---Rebuild from what is already open. A config reload re-registers every
---handler but replays no history, so without this the scene would own nothing
---it received before the reload.
---@param specs table<string, Scene.Spec>
function M.seed(specs)
  owner = {}
  for _, w in ipairs(hl.get_windows() or {}) do
    M.claim(specs, w)
  end
end

return M
