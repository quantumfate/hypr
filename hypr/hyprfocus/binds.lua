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
-- way to reach anything, including the mode panel that would undo it.
local ROOT = "root"

local captured = false

---Wrap `hl.bind` and `hl.define_submap` so every handle is filed under the tree
---being defined. Call once, before the binds are built.
function M.capture()
  if captured then
    return
  end
  captured = true

  local real_bind = hl.bind
  local real_submap = hl.define_submap

  -- `hl` is read-only everywhere else in this tree, deliberately. These two
  -- assignments are the exception, scoped to config load and to the two
  -- functions whose return values have to be grouped. The alternative is a
  -- tree name threaded through ten call sites and every helper signature
  -- between them, which couples the whole bind layer to one feature.
  -- luacheck: push globals hl

  hl.bind = function(...)
    local handle = real_bind(...)
    -- The outermost submap is the tree: everything nested under `dofus`
    -- belongs to the Dofus tree, not to a tree of its own.
    local name = stack[2] or ROOT
    trees[name] = trees[name] or {}
    table.insert(trees[name], handle)
    return handle
  end

  hl.define_submap = function(name, reset_or_fn, fn)
    stack[#stack + 1] = name
    local ok, err = pcall(real_submap, name, reset_or_fn, fn)
    stack[#stack] = nil
    if not ok then
      error(err, 0)
    end
  end
  -- luacheck: pop
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

---Enable exactly the named trees and disable the rest.
---
---`root` is always enabled whatever is asked, because the alternative is a
---desk with no leader key and no way back — including no way to reach the
---surface that would put it right.
---@param admitted string[]
---@return string[] the trees that ended up disabled
function M.admit(admitted)
  local wanted = { [ROOT] = true }
  for _, name in ipairs(admitted or {}) do
    wanted[name] = true
  end

  local disabled = {}
  for _, name in ipairs(M.names()) do
    local on = wanted[name] == true
    if not on then
      disabled[#disabled + 1] = name
    end
    for _, handle in ipairs(trees[name]) do
      -- A handle whose bind was already removed is not an error worth failing
      -- a whole transition over; the rest of the tree still has to be applied.
      pcall(function()
        handle:set_enabled(on)
      end)
    end
  end
  return disabled
end

---Drop the captured state. For tests; a config reload rebuilds the tree from
---scratch by re-evaluating, so nothing calls this at runtime.
function M.reset()
  trees = {}
  stack = { "root" }
  captured = false
end

return M
