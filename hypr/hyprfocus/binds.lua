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
local whichkey = require("hypr.lib.whichkey")

local M = {}

-- Tree name -> the keybind handles created while it was being defined.
---@type table<string, HL.Keybind[]>
local trees = {}

-- Submap nesting during config evaluation. `hl.define_submap` runs its callback
-- immediately, so a stack attributes a nested submap's binds to the tree it
-- belongs to rather than making every nesting level its own tree.
local stack = { "root" }

-- Root binds that made it into the cheatsheet, by handle, so re-attributing
-- one can move its row too.
---@type table<any, { key: string, mods: string[] }>
local root_items = {}

-- Binds outside any submap. Never withheld: they carry the leader key and the
-- way out of a submap, so a mode that dropped them would leave a desk with no
-- way to reach anything.
local ROOT = "root"

-- The tree that enters other modes. Withholding it is a trap with no exit:
-- the only way back out of a mode would be the key that mode just removed.
local MODES = "modes"

-- Described binds' closures, by description (`M.action`).
---@type table<string, function>
local actions = {}

---Record a keybind under the tree currently being defined, and return the
---handle to the caller untouched.
---
---Callers route through here rather than calling `hl.bind` directly. Wrapping
---the global instead would be far less invasive and does not work: `hl` is
---read-only in the Hyprland runtime, and assigning to it raises at config
---load — taking every module required after it down with it.
---@return HL.Keybind
---Split a combined bind spec into the words the registry renders: the mods
---only, plus the key it ends with.
---@param key string
---@return string[] mods
---@return string key
local function split_key(key)
  -- Trigger strings arrive wrapped by keystr ("+SUPER+a+"), so the wrapping
  -- pluses are the spec's own words and come off before the split: the mods
  -- are the interior words, the key is the last one.
  key = key:gsub("^%++", ""):gsub("%++$", "")
  local mods, bare = key:match("^(.*)%+([^+]+)$")
  if not bare then
    return {}, key
  end
  local mods_list = {}
  for mod in (mods or ""):gmatch("[^+]+") do
    mods_list[#mods_list + 1] = mod
  end
  return mods_list, bare
end

function M.bind(pattern, action, opts)
  local handle = hl.bind(pattern, action, opts)
  if type(action) == "function" and opts and opts.description then
    actions[opts.description] = action
  end
  -- Described binds participate in the which-key document: root binds under
  -- the registry's own root node, submap binds under their entries (recorded
  -- by submap.lua already). Undescribed binds stay private — the cheatsheet's
  -- one hard rule is that it never shows a key it cannot describe.
  -- (LEO-268: one document, by construction, for both surfaces.)
  local name = stack[2] or ROOT
  if name == ROOT then
    opts = opts or {}
    local desc = opts.description
    if desc and not opts.submap_universal then
      local mods, key = split_key(pattern or "")
      whichkey.record_root(key, mods, desc)
      -- Remembered so `M.attribute` can move the cheatsheet row with the
      -- bind; a contextual bind is registered here and re-filed straight
      -- after. A stub that hands back no handle simply records nothing.
      if handle ~= nil then
        root_items[handle] = { key = key, mods = mods }
      end
    end
  end
  trees[name] = trees[name] or {}
  table.insert(trees[name], handle)
  return handle
end

---The closure a described bind runs, by its description -- so the nested
---end-to-end tests (tests/e2e) run exactly what the key runs, since
---`send_shortcut` does not re-enter Lua binds there.
---@param description string
---@return function?
function M.action(description)
  return actions[description]
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
---@return string[] names # sorted, so callers and logs see a stable order
function M.names()
  local out = {}
  for name in pairs(trees) do
    out[#out + 1] = name
  end
  table.sort(out)
  return out
end

---Re-attribute a recorded bind to another tree.
---
---The entering leaf of a withheld submap is created while the PARENT is on
---the def-stack (root, most of the time), but it belongs to the tree it is a
---door to: in work mode the Dofus key must not exist at all — not remain a
---live key that only opens an empty, disabled submap. Attribution at leaf
---creation is how the door follows the room it opens into.
---@param handle HL.Keybind
---@param tree string the tree this bind takes its fate from
function M.attribute(handle, tree)
  local root_item = handle ~= nil and root_items[handle] or nil
  if root_item then
    whichkey.attribute_root(root_item.key, root_item.mods, tree)
  end
  for _, handles in pairs(trees) do
    for i, h in ipairs(handles) do
      if h == handle then
        table.remove(handles, i)
        break
      end
    end
  end
  trees[tree] = trees[tree] or {}
  table.insert(trees[tree], handle)
end

---@param name string
---@return integer how many binds the tree holds
function M.size(name)
  return #(trees[name] or {})
end

-- Trees withheld by something other than the mode: a leaf whose target does
-- not exist right now (a project tab the focused project has no window for).
-- A mode names what it takes and enables the rest, so without recording these
-- separately the next mode apply would hand back a key with nothing behind
-- it. Keyed by tree name, same vocabulary `admit` speaks.
---@type table<string, true>
local held = {}

-- What the last `admit` took, so `M.loaded()` can answer "which trees work
-- right now" without re-running admission.
---@type table<string, true>
local mode_withheld = {}

---Hold or release one tree independently of the mode's own admission
---(LEO: contextual project binds). A held tree stays disabled across a mode
---apply; releasing it hands it back unless the mode withholds it too.
---@param name string
---@param on boolean true = hold (disable), false = release
function M.hold(name, on)
  if name == ROOT or name == MODES then
    return
  end
  if on then
    held[name] = true
  else
    held[name] = nil
  end
  local off = held[name] == true or mode_withheld[name] == true
  for _, handle in ipairs(trees[name] or {}) do
    pcall(function()
      handle:set_enabled(not off)
    end)
  end
end

---Every tree whose binds actually work right now: what `M.names()` knows,
---minus what the mode withheld and minus what is held. This is the set the
---cheatsheet must render, so the keys it shows are the keys that fire.
---@return table<string, true>
function M.loaded()
  local out = {}
  for _, name in ipairs(M.names()) do
    if not mode_withheld[name] and not held[name] then
      out[name] = true
    end
  end
  return out
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

  mode_withheld = drop
  local disabled = {}
  for _, name in ipairs(M.names()) do
    local off = drop[name] == true or held[name] == true
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
  root_items = {}
  held = {}
  mode_withheld = {}
end

return M
