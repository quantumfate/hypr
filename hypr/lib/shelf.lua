-- Shelves: small special workspaces that slide in over the scene and hold an
-- app the desk depends on but that never takes a tile (docs/shelves.md).
--
-- Each shelf is data in `config.shelves`: a key in the `shelf` submap, the
-- window class it holds, the command that opens it, and an optional binding
-- tree. A shelf with a tree is admitted by modes like any tree; one without
-- is always reachable.
local M = {}

---@class Shelf
---@field name string shelf id; the special workspace is `shelf-<name>`
---@field key string key inside the `shelf` submap
---@field class string window class the shelf holds (window-rule grammar)
---@field cmd string what opens the app when no window of it exists
---@field desc string which-key label
---@field tree? string binding tree admitting this shelf; nil = always

---The special workspace a shelf lives on.
---@param shelf Shelf
---@return string
function M.workspace(shelf)
  return "shelf-" .. shelf.name
end

---Whether a window of the shelf's class exists anywhere.
---@param shelf Shelf
---@param windows table[] `hl.get_windows()` result
---@return boolean
function M.running(shelf, windows)
  for _, w in ipairs(windows or {}) do
    local class = w.class or ""
    if class == shelf.class or class:match("^(" .. shelf.class .. ")$") then
      return true
    end
  end
  return false
end

---What pressing a shelf key does: slide a running app's shelf in or out, or
---open the app, whose window rule then lands it on the shelf and shows it.
---Toggling while launching would open an empty shelf that the late window then
---closes. Pure, so the decision is testable.
---@param shelf Shelf
---@param windows table[]
---@return { launch: string?, toggle: string? }
function M.decide(shelf, windows)
  if M.running(shelf, windows) then
    return { toggle = M.workspace(shelf) }
  end
  return { launch = shelf.cmd }
end

---The submap entry for one shelf.
---@param shelf Shelf
---@return SubmapEntry
function M.entry(shelf)
  return {
    key = shelf.key,
    desc = shelf.desc,
    tree = shelf.tree,
    action = function()
      local d = M.decide(shelf, hl.get_windows())
      if d.launch then
        hl.dispatch(hl.dsp.exec_cmd("uwsm app -- " .. d.launch))
      else
        hl.dispatch(hl.dsp.workspace.toggle_special(d.toggle))
      end
    end,
  }
end

---Window rules that send each shelf's app to its shelf, floating and smaller
---than the monitor, so it slides in over the scene instead of tiling.
---@param shelves Shelf[]
function M.rules(shelves)
  for _, shelf in ipairs(shelves) do
    hl.window_rule({
      name = "shelf-" .. shelf.name,
      match = { initial_class = shelf.class },
      workspace = "special:" .. M.workspace(shelf),
      float = true,
      size = { "monitor_w * 0.6", "monitor_h * 0.7" },
      center = true,
    })
  end
end

return M
