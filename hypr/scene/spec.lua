-- Scene declarations, normalized (LEO-245).
--
-- The declaration is a document in the state store ($XDG_STATE_HOME
-- scenes.json, seeded on first run from `hypr/scene/defaults.lua`) — this is
-- the shape the engine reads. Normalizing here means every other layer can
-- assume blocks are order-sorted, flags are booleans, and class lists are
-- arrays — none of them re-validates.
local M = {}

---@class Scene.Block
---@field classes string[] literal class or Lua pattern, as windowrules.lua matches
---@field group boolean all matching windows live in one Hyprland group
---@field order integer position in the left-to-right tile sequence
---@field share number? fraction of the workspace's tiled span this block holds
---@field collect boolean pull members that drifted to another workspace back home
---@field guard "barred"|"deny" how a non-group block resists being grouped

---@class Scene.Spec
---@field name string workspace `default_name` — the scene's host-independent identity
---@field blocks Scene.Block[] sorted by `order`
---@field barred string[] classes that may land here but must never join a group
---@field strays "slot"|"float" what happens to a window matching no block
---@field solo_frame? boolean explicit host opt-out of the lone-tile frame (nil means default)

---Also carries a host map field except the name to fill: the document is
---keyed by workspace `default_name`, so the caller passes the key rather
---than the entry carrying a redundant one.
---@param name string
---@param raw table
---@return Scene.Spec
local function normalize(name, raw)
  local blocks = {}
  for i, block in ipairs(raw.blocks or {}) do
    blocks[i] = {
      classes = block.classes or {},
      group = block.group == true,
      order = block.order or i,
      share = block.share,
      -- Collection drags a window across workspaces, so it is opt-in: the
      -- default is that a window you moved away stays where you put it.
      collect = block.collect == true,
      -- `barred` keeps auto_group from swallowing the window on open; `deny`
      -- additionally refuses a deliberate group toggle, for a tile whose
      -- whole job is to be a fixed region beside a group.
      guard = block.guard == "deny" and "deny" or "barred",
    }
  end
  table.sort(blocks, function(a, b)
    return a.order < b.order
  end)
  return {
    name = name,
    blocks = blocks,
    barred = raw.barred or {},
    -- Slotting is the default: the desk adjusts to what is present. A scene
    -- whose geometry is a fixed region — one being captured, where a box that
    -- moves when something unrelated opens invalidates the crop — floats
    -- strays instead so the declared split never shifts.
    strays = raw.strays == "float" and "float" or "slot",
    solo_frame = raw.solo_frame,
  }
end

---@type table<string, Scene.Spec>?
local cache

---The raw document: the store's, seeded once from the default if it is empty.
---A missing store says nothing about what the user wants, so it seeds; a
---store with even one scene says a lot, so it is used as-is — emptying the
---store is a declaration too, and truth does not override it.
---@return table raw scenes keyed by default_name
local function document()
  local store = require("hypr.lib.store")
  local defaults = require("hypr.scene.defaults")
  local handle = store.define("scenes")
  local data = handle:get()
  if type(data) == "table" and next(data.scenes or {}) then
    return data.scenes
  end
  pcall(handle.put, handle, defaults)
  local seeded = handle:get()
  return (type(seeded) == "table") and seeded.scenes or defaults.scenes
end

---Every declared scene, keyed by name. Memoized: the compiler and the event
---layer both want the scenes, and normalizing twice would hand them tables
---that compare unequal — `block_for` results are used as identity.
---@return table<string, Scene.Spec>
function M.load()
  if cache then
    return cache
  end
  local out = {}
  for name, raw in pairs(document()) do
    out[name] = normalize(name, raw)
  end
  cache = out
  return out
end

---A class entry is either a literal ("Dofus.x64", "Kitty-Main") or a pattern
---("Proj-[A-Za-z0-9_-]+") — the same dual meaning class rules carry. Literals
---are tried first so a hyphenated class never trips on `-` being a Lua-pattern
---quantifier.
---@param class string?
---@param patterns string[]
---@return boolean
function M.class_matches(class, patterns)
  if not class then
    return false
  end
  for _, entry in ipairs(patterns) do
    if class == entry or class:match("^(" .. entry .. ")$") then
      return true
    end
  end
  return false
end

---The block owning `class`, or nil.
---@param spec Scene.Spec
---@param class string?
---@return Scene.Block?
function M.block_for(spec, class)
  for _, block in ipairs(spec.blocks) do
    if M.class_matches(class, block.classes) then
      return block
    end
  end
  return nil
end

return M
