-- Scene declarations, normalized (LEO-245).
--
-- The declaration is a document in the state store ($XDG_STATE_HOME
-- scenes.json, seeded on first run from `hypr/scene/defaults.lua`) — this is
-- the shape the engine reads. Normalizing here means every other layer can
-- assume blocks are order-sorted, flags are booleans, and class lists are
-- arrays — none of them re-validates.
local M = {}

---@class Scene.Companion
---@field class string the companion window's identity class
---@field command string what opens it, run the first time in

---@class Scene.Block
---@field classes string[] literal class or Lua pattern, as windowrules.lua matches
---@field group boolean all matching windows live in one Hyprland group
---@field order integer position in the left-to-right tile sequence
---@field share number? fraction of the workspace's tiled span this block holds
---@field collect boolean pull members that drifted to another workspace back home
---@field guard "barred"|"deny" how a non-group block resists being grouped
---@field spawn Scene.Companion? the companion window this block's presence keeps alive

---@class Scene.Spec
---@field name string workspace `default_name` — the scene's host-independent identity
---@field blocks Scene.Block[] sorted by `order`
---@field barred string[] classes that may land here but must never join a group
---@field strays "slot"|"float" what happens to a window matching no block
---@field solo_frame? boolean explicit host opt-out of the lone-tile frame (nil means default)
---@field bindings string[] binding trees admitted while this scene is active
---@field moods string[] mood tags this scene matches
---@field machines table<string, table> machine-specific geometry overrides

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
      -- A companion is declared whole or not at all: a block naming the
      -- window it opens by humming is worse than one the user opens by hand.
      spawn = (type(block.spawn) == "table" and block.spawn.class and block.spawn.command)
          and { class = block.spawn.class, command = block.spawn.command }
        or nil,
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
    bindings = raw.bindings or {},
    moods = raw.moods or {},
    machines = raw.machines or {},
  }
end

---@type table<string, Scene.Spec>?
local cache

---The raw document: the store's, or the seed's if the store does not say.
---
---Migration is one step back and one step forward: a store absent at
---$QF_STORE adopts the legacy document (the previous generation's location)
---and WRITES it forward, so moving the collection needs no tooling and no
---second read path afterwards. A store still carrying an older seed
---generation is re-seeded, because "declared" cannot mean a document that
---predates the features it governs — that is how a shipped default idea was
---born before part of it existed. Emptying the store stays a declaration
---(absent = seed, present = truth, once the version agrees).
---@return table raw scenes keyed by default_name
local function document()
  local store = require("hypr.lib.store")
  local defaults = require("hypr.scene.defaults")
  local handle = store.define("scenes")
  local data = handle:get()
  if type(data) == "table" then
    -- A store written before the current seed (or migrated without exactly
    -- the version key from an older file that never wore one) re-seeds once,
    -- which is the cheapest way to adopt additively without renegotiating
    -- every field the user may have touched.
    if (data.version or 0) < defaults.version then
      pcall(handle.put, handle, defaults)
      data = handle:get()
    end
    if type(data) == "table" and next(data.scenes or {}) then
      return data.scenes
    end
    return defaults.scenes
  end
  -- Nothing at the new location at all: seed (and the store grows on the
  -- first write, thinking regardless of whether the store write lands).
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
