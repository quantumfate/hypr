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
---@field max_spawns number how many of `class` the engine keeps alive while
---the block has members (never fewer than 1; a cap only constrains what the
---engine itself opens, not what already exists)
---@field auto_start boolean? if true, keep the companion alive whenever this
---scene is active, even when no member window is currently present

---@class Scene.Block
---@field classes string[] literal class or Lua pattern, as windowrules.lua matches
---@field group boolean all matching windows live in one Hyprland group
---@field order integer position in the left-to-right tile sequence
---@field share number? fraction of the workspace's tiled span this block holds
---@field guard "barred"|"deny" how a non-group block resists being grouped
---@field spawns Scene.Companion[]? the companion windows this block's
---presence keeps alive — one per class, the singular declaration folded in
---by `normalize_spawns`
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
---@field gaps_in number? scene-declared inner gap (LEO-397); wins over the host
---workspace-spec and the global `general:gaps_in` where set
---@field gaps_out Scene.CssGap|number? scene-declared outer gap; same precedence
---@field docks table<string, Dock.Spec|false>? isle id -> where it docks (docs/scenes.md "Docks")

---Also carries a host map field except the name to fill: the document is
---keyed by workspace `default_name`, so the caller passes the key rather
---than the entry carrying a redundant one.
---@param name string
---@param raw table
---@return Scene.Spec
---@class Deck.Column
---@field order integer left-to-right position, 1..3
---@field share number? fraction of the row this column holds
---@field classes string[]? literal class or Lua pattern subscribing a window
---@field deck string? subscription name for the `deck:<name>` self-declaration tag

---A `deck` scene's `columns`, normalized the same shallow way `blocks` is
---(order-sorted, class list defaulted). Additive: a scene that never
---declares `columns` (every scene today) gets an empty list, same as an
---undeclared `blocks` already does — see docs/deck.md.
---@param raw table[]?
---@return Deck.Column[]
local function normalize_columns(raw)
  local columns = {}
  for i, column in ipairs(raw or {}) do
    columns[i] = {
      order = column.order or i,
      share = column.share,
      classes = column.classes or {},
      deck = type(column.deck) == "string" and column.deck or nil,
    }
  end
  table.sort(columns, function(a, b)
    return a.order < b.order
  end)
  return columns
end

---The declared spawn cap, normalized: a positive whole number as-is, anything
---else — missing, 0, negative, fractional — falls back to 1, today's
---behaviour. Same shape as a half-declared spawn being dropped: a bad value
---must not refuse the whole scene declaration.
---@param value unknown
---@return number
local function normalize_max_spawns(value)
  local n = tonumber(value)
  if type(n) == "number" and n >= 1 and n == math.floor(n) and n < math.huge then
    return n
  end
  return 1
end

---One declared companion, whole or not at all: a block naming the window it
---opens by humming is worse than one the user opens by hand. The cap
---defaults to 1 (today's behaviour) and normalizes like every other numeric:
---out-of-range values fall back, never refuse the scene.
---@param raw unknown
---@return Scene.Companion?
local function normalize_spawn(raw)
  if type(raw) ~= "table" or not raw.class or not raw.command then
    return nil
  end
  return {
    class = raw.class,
    command = raw.command,
    max_spawns = normalize_max_spawns(raw.max_spawns),
    auto_start = raw.auto_start == true,
  }
end

---A block's declared companions as one list: the singular `spawn` and the
---plural `spawns` fold here, so a consumer reads one shape — a list of the
---per-class companions the block keeps alive while any of its members
---stands. The singular stays valid; `spawns` just lets one block name
---several different companion classes from the same presence (a console and
---each of its browsers, say). Entries are dropped whole when bad, never a
---scene refused.
---@param block table
---@return Scene.Companion[]?
local function normalize_spawns(block)
  local out = {}
  local single = normalize_spawn(block.spawn)
  if single then
    out[#out + 1] = single
  end
  if type(block.spawns) == "table" then
    for _, raw in ipairs(block.spawns) do
      local entry = normalize_spawn(raw)
      if entry then
        out[#out + 1] = entry
      end
    end
  end
  return #out > 0 and out or nil
end

---Log one dropped dock entry — same shape as a half-declared `spawn` (the
---scene survives), but a dock also names what it dropped and why, since
---there is no companion window to notice the gap by its absence.
---@param scene string
---@param isle string
---@param reason string
local function report_dock_dropped(scene, isle, reason)
  require("hypr.lib.trace").emit({
    stage = "admit",
    event = "dock_dropped",
    decision = "drop",
    scene = scene,
    isle = isle,
    reason = reason,
  })
end

---Validate one dock entry and its `fallback` chain, recursively. A bad
---level is dropped from the chain (its own `fallback`, if any, is not
---consulted either — a broken link never smuggles a later one through)
---rather than refusing the isle's whole declaration.
---@param scene string
---@param isle string
---@param entry unknown
---@return Dock.Spec|false|nil
local function normalize_dock_entry(scene, isle, entry)
  if entry == false then
    return false
  end
  local dock = require("hypr.lib.dock")
  if not dock.valid_entry(entry) then
    report_dock_dropped(scene, isle, "bad at/of/orientation")
    return nil
  end
  local out = { at = entry.at, of = entry.of, orientation = entry.orientation }
  if entry.fallback ~= nil then
    out.fallback = normalize_dock_entry(scene, isle, entry.fallback)
  end
  return out
end

---Every isle the scene declares a dock for, dropping bad entries in place
---(docs/scenes.md "Docks"). Additive: a scene that never declares `docks`
---(every scene today) gets an empty table, same as `columns`.
---@param name string
---@param raw table<string, unknown>?
---@return table<string, Dock.Spec|false>
local function normalize_docks(name, raw)
  local out = {}
  for isle, entry in pairs(raw or {}) do
    local normalized = normalize_dock_entry(name, isle, entry)
    if normalized ~= nil then
      out[isle] = normalized
    end
  end
  return out
end

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
      -- The companions this block's presence keeps alive, per the fold above:
      -- a block may declare one (`spawn`) or several (`spawns`), and every
      -- consumer reads the one list.
      spawns = normalize_spawns(block),
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
    -- Layout opt-in (docs/deck.md): every scene defaults to "scene"; only
    -- "deck" changes anything, and no live scene declares it yet.
    layout = raw.layout == "deck" and "deck" or "scene",
    columns = normalize_columns(raw.columns),
    gaps_in = tonumber(raw.gaps_in),
    gaps_out = raw.gaps_out,
    docks = normalize_docks(name, raw.docks),
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
---@param handle Store.Handle
---@return table raw scenes keyed by default_name
local function document(handle)
  local declaration = handle:get()
  if type(declaration) ~= "table" or not declaration.base then
    report_missing("no declaration in the store")
    return {}
  end
  pcall(migrate_legacy, require("hypr.lib.store"), handle, declaration)
  local scenes = declaration.base.scenes
  if type(scenes) ~= "table" or not next(scenes) then
    report_missing("declaration has no base.scenes")
    return {}
  end
  return scenes
end

-- The store mtime `cache` was normalized against (LEO-397). A store edit
-- (scene blocks, gaps, ...) bumps the handle's mtime, so the next `M.load()`
-- re-normalizes instead of handing back a declaration frozen since whenever
-- this Lua state last required this module — no `hyprctl reload` needed.
---@type string?
local cached_mtime

---Re-publish the resolved per-workspace gap the aligned bar subscribes to
---(quickshell `bar_follows_scene_gaps`) the moment this table is rebuilt — a
---scene/gaps edit bumped the store mtime, and this first pass that notices it
---is also the pass whose gaps the compositor tiles at next. conf/host.lua
---publishes the same map at config load; this keeps a runtime edit from
---drifting stale on the bar side until a reload. Quickshell only reads; it
---never derives, so the exposed value is always exactly what hyprland resolved.
---Guarded: a build that has not finalized host specs yet, or a test fixture
---with neither `config` nor a live compositor, has nothing to fold.
---@param scenes table<string, Scene.Spec>
local function publish_resolved(scenes)
  pcall(function()
    -- Only the desktop runtime publishes (it is the one that exports QF_STORE);
    -- a bare unit-test run must never write the real geometry store.
    if not os.getenv("QF_STORE") then
      return
    end
    local config = rawget(_G, "config")
    local specs = config and config.host and config.host.workspaces and config.host.workspaces.workspace_specs
    if not specs then
      return
    end
    local function live(key)
      local ok, value = pcall(hl.get_config, key)
      return ok and value or nil
    end
    local defaults = config.default_gaps or {}
    local default_gaps_out = live("general.gaps_out") or defaults.gaps_out
    -- The bar's inset is the distance to the visible window, which the
    -- compositor builds from the workspace rule's gaps_in and the border on top
    -- of the layout's box (hypr/lib/geometry.lua's `resolved_gaps`); read them
    -- live so a config edit never drifts from what is actually tiled.
    local inner = {
      gaps_in = live("general.gaps_in") or defaults.gaps_in,
      border = live("general.border_size") or 0,
    }
    -- A scene edit can leave the resolved dock map identical by value while
    -- the declaration behind it changed, so the publish tail's write-suppressor
    -- is dropped here rather than trusted to notice.
    require("hypr.scene.dock_publish").invalidate()
    require("hypr.lib.store").define("geometry"):set({
      workspaces = require("hypr.lib.geometry").resolved_gaps(scenes, specs, default_gaps_out, inner),
    })
  end)
end

---Every declared scene, keyed by name. Memoized against the store's mtime: the
---compiler and the event layer both want the scenes, and normalizing twice
---would hand them tables that compare unequal — `block_for` results are used
---as identity — but a stale-forever cache would mean a scene/gaps edit never
---reaches a running desk without a full config reload.
---@return table<string, Scene.Spec>
function M.load()
  local ok, handle = pcall(require("hypr.lib.store").define, "hyprfocus")
  if not ok then
    report_missing(tostring(handle))
    return cache or {}
  end
  -- A handle without :mtime() (test fixtures stub only get/put) can't prove
  -- freshness, so it never gets the cache -- correct for tests, which swap
  -- the fake store's data and expect the very next load() to see it.
  local has_mtime, mtime = pcall(function()
    return handle:mtime()
  end)
  if has_mtime and cache and mtime == cached_mtime then
    return cache
  end
  local out = {}
  for name, raw in pairs(document(handle)) do
    out[name] = normalize(name, raw)
  end
  cache = out
  cached_mtime = mtime
  publish_resolved(out)
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
