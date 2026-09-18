-- Scene declarations, normalized (LEO-245).
--
-- The declaration is the hyprfocus store's `base.scenes` ($QF_STORE
-- hyprfocus.json, the one scene table) — this is the shape the engine reads.
-- Normalizing here means every other layer can assume blocks are
-- order-sorted, flags are booleans, and class lists are arrays — none of them
-- re-validates.
local M = {}

---@class Scene.Companion
---@field class string the companion window's identity class
---@field command string what opens it, run the first time in

---@class Scene.Block
---@field classes string[] literal class or Lua pattern, as windowrules.lua matches
---@field group boolean all matching windows live in one Hyprland group
---@field order integer position in the left-to-right tile sequence
---@field share number? fraction of the workspace's tiled span this block holds
---@field guard "barred"|"deny" how a non-group block resists being grouped
---@field spawn Scene.Companion? the companion window this block's presence keeps alive
---@field slot string? identity suffix (LEO-364): with this set, the block only
---claims a window of `classes` that already carries the Hyprland tag
---`slot:<slot>` — `hypr/scene/identify.lua` is what stamps it, at launch, on
---one of several same-class windows. Two blocks may share the same `classes`
---entry (`ambiguous_classes` still flags that, correctly, as a class-only
---conflict) as long as each names a distinct `slot`.

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
      -- `barred` keeps auto_group from swallowing the window on open; `deny`
      -- additionally refuses a deliberate group toggle, for a tile whose
      -- whole job is to be a fixed region beside a group.
      guard = block.guard == "deny" and "deny" or "barred",
      -- A companion is declared whole or not at all: a block naming the
      -- window it opens by humming is worse than one the user opens by hand.
      spawn = (type(block.spawn) == "table" and block.spawn.class and block.spawn.command)
          and { class = block.spawn.class, command = block.spawn.command }
        or nil,
      slot = type(block.slot) == "string" and block.slot or nil,
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

---Fold a surviving legacy `scenes.json` into the declaration once, then move
---it aside so the fold never runs twice. Unedited scenes are dropped.
---@param store table the store module
---@param handle Store.Handle the declaration's handle
---@param declaration table
local function migrate_legacy(store, handle, declaration)
  local legacy = store.define("scenes")
  local path = legacy.path
  local file = path and io.open(path, "r")
  if not file then
    return
  end
  file:close()
  local _, folded = require("hypr.scene.migrate").fold(declaration, legacy:get())
  if #folded > 0 then
    handle:put(declaration)
  end
  os.rename(path, path .. ".migrated")
  require("hypr.lib.trace").emit({
    stage = "admit",
    event = "scenes_migrated",
    decision = "fold",
    reason = #folded > 0 and table.concat(folded, ",") or "unedited",
  })
end

---Report that no scene table could be read. The engine stays inert: no
---placement and no grouping until the declaration is seeded.
---@param reason string
local function report_missing(reason)
  require("hypr.lib.trace").emit({
    stage = "admit",
    event = "scenes_missing",
    decision = "inert",
    reason = reason,
  })
  pcall(function()
    require("hypr.lib.notify"):notify(
      "hyprfocus: no scene declaration (" .. reason .. "); run ,hyprfocus seed",
      0,
      "ERROR"
    )
  end)
end

---The raw scene table: the hyprfocus declaration's `base.scenes`, the only
---stored scene document (docs/scenes.md, "Source of truth").
---@return table raw scenes keyed by default_name
local function document()
  local store = require("hypr.lib.store")
  local ok, handle = pcall(store.define, "hyprfocus")
  local declaration = ok and handle:get() or nil
  if type(declaration) ~= "table" or not declaration.base then
    report_missing(ok and "no declaration in the store" or tostring(handle))
    return {}
  end
  pcall(migrate_legacy, store, handle, declaration)
  local scenes = declaration.base.scenes
  if type(scenes) ~= "table" or not next(scenes) then
    report_missing("declaration has no base.scenes")
    return {}
  end
  return scenes
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

---Whether `tags` (a live window's Hyprland tags) contains `tag`.
---@param tags string[]?
---@param tag string
---@return boolean
local function has_tag(tags, tag)
  for _, t in ipairs(tags or {}) do
    if t == tag then
      return true
    end
  end
  return false
end

---Every block whose `classes` match, in declaration order. `block_for` takes
---the first; this exposes the rest so a caller (the identify-stage logger,
---LEO-355's follow-up) can see and report an ambiguous class instead of the
---later blocks silently never filling.
---
---A block with `slot` set (LEO-364) additionally requires `tags` to already
---carry `slot:<slot>` — a bare class match is not enough to pick between two
---same-class slot blocks. `tags` is optional so existing class-only callers
---are unaffected.
---@param spec Scene.Spec
---@param class string?
---@param tags string[]?
---@return Scene.Block[]
function M.block_candidates(spec, class, tags)
  local out = {}
  for _, block in ipairs(spec.blocks) do
    if M.class_matches(class, block.classes) and (not block.slot or has_tag(tags, "slot:" .. block.slot)) then
      out[#out + 1] = block
    end
  end
  return out
end

---The block owning `class` (and, for a slot block, `tags`), or nil.
---First-match by declaration order: kept deterministic and documented rather
---than refused, since a scene author can always resolve a real ambiguity
---with `ambiguous_classes` below.
---@param spec Scene.Spec
---@param class string?
---@param tags string[]?
---@return Scene.Block?
function M.block_for(spec, class, tags)
  return M.block_candidates(spec, class, tags)[1]
end

---Every `slot`-bearing block whose `classes` match `class`, in declaration
---order, regardless of what any window is tagged yet — the pool
---`hypr/scene/identify.lua` picks the next free slot from. Declaration
---order is `hypr/scene/spec.lua`'s `order`-sort, so slot assignment is
---deterministic across a reload.
---@param spec Scene.Spec
---@param class string?
---@return Scene.Block[]
function M.slot_candidates(spec, class)
  local out = {}
  for _, block in ipairs(spec.blocks) do
    if block.slot and M.class_matches(class, block.classes) then
      out[#out + 1] = block
    end
  end
  return out
end

---Declared class entries claimed by more than one of the scene's own blocks —
---a static check over the declaration itself, not a live window's class, so
---an author sees the conflict without needing a matching window open. Order
---follows first appearance across the blocks.
---@param spec Scene.Spec
---@return string[]
function M.ambiguous_classes(spec)
  local count, order = {}, {}
  for _, block in ipairs(spec.blocks) do
    for _, entry in ipairs(block.classes) do
      -- A slot tells two blocks of one class apart, so only class-only
      -- claims count toward ambiguity.
      local key = block.slot and (entry .. "@" .. block.slot) or entry
      if not count[key] then
        order[#order + 1] = { key = key, class = entry }
      end
      count[key] = (count[key] or 0) + 1
    end
  end
  local out = {}
  for _, entry in ipairs(order) do
    if count[entry.key] > 1 then
      out[#out + 1] = entry.class
    end
  end
  return out
end

return M
