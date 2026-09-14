-- Binding trees, held by name so a mode can admit or withhold them.
--
-- A binding tree is a resource like any other: the Dofus submap is meaningful
-- when a Dofus group is on screen and meaningless otherwise, and outside game
-- mode its keys should not exist rather than being pressed and ignored. That
-- is the editor's buffer-local model — a buffer brings its own mappings and
-- takes them away again.
--
-- Withholding a tree is what replaces asking permission. The shipped
-- alternative spawned a subprocess from inside a bind handler to ask the shell
-- whether the action was allowed, on every press, on the compositor thread. A
-- disabled bind answers the same question with no question.
--
-- Handles are captured by wrapping `hl.bind` for the duration of config load,
-- rather than threading a tree name through ten call sites and their
-- signatures. There is no API to enumerate binds afterwards, so capturing at
-- creation is the only moment they can be grouped at all.
local M = {}

-- Tree name -> the keybind handles created while it was being defined.
---@type table<string, HL.Keybind[]>
local trees = {}

-- Submap nesting during config evaluation. `hl.define_submap` runs its callback
-- immediately, so a stack attributes a nested submap's binds to the tree it
-- belongs to rather than making every nesting level its own tree.
local stack = { "root" }

-- Binds outside any submap. Never withheld: they carry the leader key and the
-- way out of a submap, so a mode that dropped them would leave a desk with no
-- way to reach anything.
local ROOT = "root"

-- The tree that enters other modes. Withholding it is a trap with no exit:
-- the only way back out of a mode would be the key that mode just removed.
local MODES = "modes"

---Record a keybind under the tree currently being defined, and return the
---handle to the caller untouched.
---
---Callers route through here rather than calling `hl.bind` directly. Wrapping
---the global instead would be far less invasive and does not work: `hl` is
---read-only in the Hyprland runtime, and assigning to it raises at config
---load — taking every module required after it down with it.
---@return HL.Keybind
function M.bind(...)
  local handle = hl.bind(...)
  -- The outermost submap is the tree: everything nested under `dofus` belongs
  -- to the Dofus tree, not to a tree of its own.
  local name = stack[2] or ROOT
  trees[name] = trees[name] or {}
  table.insert(trees[name], handle)
  return handle
end

---Define a submap, tracking the nesting so binds inside it are attributed to
---the tree they belong to.
---@param name string
---@param reset_or_fn string|function
---@param fn function?
function M.submap(name, reset_or_fn, fn)
  stack[#stack + 1] = name
  local ok, err = pcall(hl.define_submap, name, reset_or_fn, fn)
  stack[#stack] = nil
  if not ok then
    error(err, 0)
  end
end

---Every tree that has at least one bind.
---@return string[] sorted, so callers and logs see a stable order
function M.names()
  local out = {}
  for name in pairs(trees) do
    out[#out + 1] = name
  end
  table.sort(out)
  return out
end

---@param name string
---@return integer how many binds the tree holds
function M.size(name)
  return #(trees[name] or {})
end

---Withhold exactly the named trees, and enable everything else.
---
---The default is on, and that is the load-bearing part. A tree the
---declaration never mentions is far more likely to be a gap in the
---declaration than an intention to remove it — and the cost of the two
---mistakes is not remotely symmetric. Leaving an unnamed tree enabled means a
---mode does not take away as much as it meant to. Disabling it means a desk
---with no terminal and no way back, which is a reboot.
---
---So a mode names what it takes. It does not enumerate what it keeps.
---
---`root` and the modes tree are refused whatever is asked. Root carries the
---leader key; the modes tree is the only way into another mode, so withholding
---it leaves the exit behind the door it just locked.
---@param withheld string[] trees this mode takes away
---@return string[] the trees actually disabled
function M.admit(withheld)
  local drop = {}
  for _, name in ipairs(withheld or {}) do
    if name ~= ROOT and name ~= MODES then
      drop[name] = true
    end
  end

  local disabled = {}
  for _, name in ipairs(M.names()) do
    local off = drop[name] == true
    if off then
      disabled[#disabled + 1] = name
    end
    for _, handle in ipairs(trees[name]) do
      -- A handle whose bind was already removed is not an error worth failing
      -- a whole transition over; the rest of the tree still has to be applied.
      pcall(function()
        handle:set_enabled(not off)
      end)
    end
  end
  return disabled
end

---Drop the recorded state. For tests; a config reload rebuilds the trees from
---scratch by re-evaluating, so nothing calls this at runtime.
function M.reset()
  trees = {}
  stack = { ROOT }
end

return M
