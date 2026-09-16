local whichkey = require("hypr.lib.whichkey")
local qs = require("hypr.lib.qs")
local hyprfocus_binds = require("hypr.hyprfocus.binds")

local M = {}

-- Which-key style submap navigation.
--
-- Hyprland submaps are a single global runtime state, so nesting needs a stack
-- on our side to know where "back" and "out" lead. This module owns that stack
-- and is the single way submaps are built in this config (via M.tree), so
-- navigation is consistent everywhere:
--   * entering a group      -> push, so escape can return to the parent
--   * using a leaf action    -> pop the whole tree, back to where we started
--   * escape                 -> pop one level (the previous tree member)
--   * shift+escape           -> hard reset to the root submap

-- The path of submap names currently entered. #stack == depth in the tree.
---@type string[]
local stack = {}
-- Per-submap lifecycle callbacks, keyed by submap name. `enter` fires just
-- after a submap becomes active; `leave` fires when it is popped (via back,
-- a leaf action's exit, or reset). Used to sync external state — e.g. tell the
-- Quickshell UI which team submap is active. Registered from tree specs.
---@type table<string, { enter?: fun(), leave?: fun() }>
local hooks = {}
-- The submap that was active before the tree's root was entered; where a leaf
-- action or a full exit returns to.
local base = "reset"

---@param mods string[]
---@return string
local function keystr(mods)
  return "+" .. table.concat(mods, "+") .. "+"
end

---@param action HL.Dispatcher|fun()
local function run(action)
  if type(action) == "function" then
    action()
  else
    hl.dispatch(action)
  end
end

---Fire a submap's lifecycle callback, if registered.
---@param name string
---@param phase "enter"|"leave"
local function fire(name, phase)
  local h = hooks[name]
  if h and h[phase] then
    h[phase]()
  end
end

---Enter a submap, remembering where we came from.
---@param name string
function M.enter(name)
  if #stack == 0 then
    base = hl.get_current_submap()
  end
  stack[#stack + 1] = name
  hl.dispatch(hl.dsp.submap(name))
  fire(name, "enter")
end

---Go back one level: to the parent submap, or the base if at the top.
function M.back()
  local leaving = table.remove(stack)
  if leaving then
    fire(leaving, "leave")
  end
  if #stack == 0 then
    qs.call("whichkey", "dismiss")
  end
  hl.dispatch(hl.dsp.submap(stack[#stack] or base))
end

---Leave the whole tree: clear the stack and return to the base submap. This is
---the which-key "picked a command, close the menu" behaviour.
function M.exit()
  for i = #stack, 1, -1 do
    fire(stack[i], "leave")
  end
  stack = {}
  -- Dismiss before dispatching the reset: the which-key overlay starts fading
  -- out ahead of the submap event, so once the base map is live there is no
  -- lingering surface to swallow a keystroke meant for a base binding.
  qs.call("whichkey", "dismiss")
  hl.dispatch(hl.dsp.submap(base))
end

---Hard reset to the root ("reset") submap regardless of depth.
function M.reset()
  for i = #stack, 1, -1 do
    fire(stack[i], "leave")
  end
  stack = {}
  qs.call("whichkey", "dismiss")
  hl.dispatch(hl.dsp.submap("reset"))
end

-- SubmapEntry / SubmapSpec are defined in hypr/types.lua.

---Full "+MOD+...+key+" trigger string for an entry.
---@param e SubmapEntry
---@return string
local function combo(e)
  local parts = {}
  for _, m in ipairs(e.mods or {}) do
    parts[#parts + 1] = m
  end
  parts[#parts + 1] = e.key
  return keystr(parts)
end

---@param name string
---@param entries SubmapEntry[]
---@param sticky boolean whether leaves stay in the submap by default (modal)
local function define(name, entries, sticky)
  hyprfocus_binds.submap(name, function()
    for _, e in ipairs(entries) do
      if e.entries then
        local child = e.name or (name .. "-" .. e.key)
        local child_sticky = e.sticky
        if child_sticky == nil then
          child_sticky = sticky
        end
        hooks[child] = { enter = e.on_enter, leave = e.on_leave }
        whichkey.register(child, name, e.entries)
        hyprfocus_binds.bind(combo(e), function()
          if e.action then
            run(e.action)
          end
          M.enter(child)
        end, { description = (e.desc or child) .. "…" })
        define(child, e.entries, child_sticky)
      else
        local stay = e.stay
        if stay == nil then
          stay = sticky
        end
        local opts = {}
        for k, v in pairs(e.opts or {}) do
          opts[k] = v
        end
        opts.description = opts.description or e.desc
        opts.repeating = e.repeating
        local handle = hyprfocus_binds.bind(combo(e), function()
          if e.action then
            run(e.action)
          end
          -- `opens` means nest: the leaf enters another submap and stays there
          -- (LEO-327). A plain leaf still exits the tree after its action.
          if not stay and not e.opens then
            M.exit()
          end
        end, opts)
        -- An enter-only leaf (`opens`) lives at the parent's def-time but
        -- belongs to the tree it is a door into: withholding the tree takes
        -- the leaf with it, so a mode removes the key and the room together.
        if e.opens then
          hyprfocus_binds.attribute(handle, e.opens)
        elseif e.tree then
          -- A leaf admitted on its own: it sits in this submap but a mode
          -- loads or withholds it by its own tree name.
          hyprfocus_binds.attribute(handle, e.tree)
        end
      end
    end
    -- The way out is a root fact, and the file placement HAS to match the
    -- claim: these binds are created inside the submap body, where stack[2]
    -- already names the submap, so without re-attribution the escape binds
    -- filed under the tree — and a mode withholding that tree took the way
    -- out with the room (the desk went unresponsive once the empty submap
    -- was reachable). Re-anchoring to root is what the comment claims.
    hyprfocus_binds.attribute(
      hyprfocus_binds.bind(keystr({ "escape" }), function()
        M.back()
      end),
      "root"
    )
    hyprfocus_binds.attribute(
      hyprfocus_binds.bind(keystr({ "SHIFT", "escape" }), function()
        M.reset()
      end),
      "root"
    )
  end)
end

---Define a submap tree. Entries with `entries` are navigable groups; entries
---with `action` are leaves that run then close the tree (unless `stay`, or the
---submap is `sticky`, in which case leaves stay by default).
---@param spec SubmapSpec
function M.tree(spec)
  hooks[spec.name] = { enter = spec.on_enter, leave = spec.on_leave }
  whichkey.register(spec.name, nil, spec.entries)
  -- Trees entered by a key carry the leader here; trees entered programmatically
  -- (e.g. the alt-tab picker) omit `mods`. The entering leaf still belongs to
  -- the destination tree (LEO-303), so withholding the tree takes its door.
  if spec.mods then
    local leader = hyprfocus_binds.bind(keystr(spec.mods), function()
      M.enter(spec.name)
    end, { description = (spec.desc or spec.name) .. "…" })
    hyprfocus_binds.attribute(leader, spec.name)
  end
  define(spec.name, spec.entries, spec.sticky or false)
end

return M
