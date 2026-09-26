-- Where a deck-layout scene's windows go, as arithmetic and a hold list.
--
-- Pure, mirroring hypr/scene/layout.lua: a scene, the tiles present, the
-- scroll position per column, and the work area go in; a box per VISIBLE
-- tile and a list of addresses to HOLD off the workspace come out. No `hl`,
-- no dispatch, no timers. See docs/deck.md for the contract this implements.
--
-- Why a hold list instead of an off-viewport box: a spike in the nested e2e
-- instance (LEO-349) placed a second tiled target a full work-area height
-- below the visible area via `target:place`. Hyprland did not honour it —
-- the second window's reported geometry was not the requested box, it was
-- silently restacked inside the visible area instead. A layout cannot rely
-- on off-screen placement to hide a deck's non-visible windows; they must
-- leave the workspace's tiled set entirely (a special "hold" workspace, the
-- same mechanism `hypr/lib/minimize.lua` and `hypr/hyprfocus/hold.lua`
-- already use), which is a dispatch this pure module only reports the need
-- for — it never performs it.
--
-- `opts.gaps_out` is a CssGap (number or {top,right,bottom,left} table),
-- the same shape `hypr/scene/layout.lua` accepts; the provider used to
-- collapse it to one scalar, which broke asymmetric outer gaps.
local layout = require("hypr.scene.layout")

local M = {}

local MIN_COLUMNS = 1
local MAX_COLUMNS = 3

---@class Deck.Column
---@field order integer left-to-right position, 1..3
---@field share number? fraction of the row this column holds
---@field classes string[]? literal class or Lua pattern subscribing a window
---@field deck string? subscription name: a window carrying the Hyprland tag
---`deck:<name>` joins this column regardless of class (a window "declaring
---itself in"), the same identity-tag pattern as a scene block's `slot`

---@class Deck.Spec
---@field name string workspace default_name
---@field columns Deck.Column[] 1..3 entries, sorted by `order`

---Whether a scene's declaration opts into the deck layout. Every scene
---defaults to `scene` (fixed blocks); `layout = "deck"` is the one opt-in.
---A scene that never sets it — Dofus included — keeps `scene` and must
---never see scroll/flip behaviour.
---@param scene { layout: string? }
---@return boolean
function M.applies(scene)
  return scene ~= nil and scene.layout == "deck"
end

---Whether `tags` carries the deck self-declaration `deck:<name>`.
---@param tags string[]?
---@param name string
---@return boolean
local function has_deck_tag(tags, name)
  for _, t in ipairs(tags or {}) do
    if t == "deck:" .. name then
      return true
    end
  end
  return false
end

---The column a tile subscribes to: by `classes` pattern match (the same
---grammar `hypr/scene/spec.lua`'s `class_matches` uses), or by carrying the
---column's own `deck:<name>` tag — a window declaring itself in without its
---class being listed at all. First match by column `order`, deterministic
---like `spec.block_for`.
---@param spec Deck.Spec
---@param tile Scene.Tile
---@return Deck.Column?
function M.column_for(spec, tile)
  for _, column in ipairs(spec.columns) do
    if column.deck and has_deck_tag(tile.tags, column.deck) then
      return column
    end
  end
  for _, column in ipairs(spec.columns) do
    if column.classes then
      for _, entry in ipairs(column.classes) do
        if tile.class == entry or (tile.class and tile.class:match("^(" .. entry .. ")$")) then
          return column
        end
      end
    end
  end
  return nil
end

---Every tile grouped by the column it subscribes to — a column's "deck" of
---windows, unclaimed tiles dropped (a deck scene has no stray catch-all;
---every column names its own membership explicitly, unlike a `scene` block's
---fallback strays).
---
---Ordering within a column: the recorded `order` (per-column address list,
---`hypr/scene/deck_order.lua`) leads, so the strip walks the arrangement the
---user built it into — a reload re-enumerates windows and must not scramble
---that. Anything the record does not name — a freshly opened window, or one
---whose recorded place falls outside the live set — is appended afterwards in
---arrival order; the provider folds it into the record on the same pass, so
---"new" means exactly "not yet recorded". With no recorded order (a
---brand-new deck) every tile stays in arrival order, today's behaviour.
---@param spec Deck.Spec
---@param tiles Scene.Tile[]
---@param order table<integer, string[]>? recorded address list per column
---@return table<integer, Scene.Tile[]> stacks keyed by column order
function M.stacks(spec, tiles, order)
  local out = {}
  for _, tile in ipairs(tiles) do
    local column = M.column_for(spec, tile)
    if column then
      out[column.order] = out[column.order] or {}
      local list = out[column.order]
      list[#list + 1] = tile
    end
  end
  if not order then
    return out
  end
  for column_order, list in pairs(out) do
    local recorded = order[column_order]
    if recorded and #recorded > 0 then
      local by_address = {}
      for _, tile in ipairs(list) do
        if tile.address then
          by_address[tile.address] = tile
        end
      end
      local sorted = {}
      for _, address in ipairs(recorded) do
        local tile = by_address[address]
        if tile then
          sorted[#sorted + 1] = tile
          by_address[address] = nil
        end
      end
      -- Recorded addresses that still stand come first, in record order; the
      -- survivors of the arrival pass fill the tail, keeping arrival order.
      for _, tile in ipairs(list) do
        if tile.address and by_address[tile.address] then
          sorted[#sorted + 1] = tile
        end
      end
      out[column_order] = sorted
    end
  end
  return out
end

---Clamp a scroll index into a stack that may have shrunk (a window closed)
---or grown, so a closed window can never strand a column past its end.
---Empty stacks clamp to 0 (nothing to show).
---@param index integer?
---@param count integer
---@return integer
function M.clamp_scroll(index, count)
  if count <= 0 then
    return 0
  end
  index = index or 1
  if index < 1 then
    return 1
  end
  if index > count then
    return count
  end
  return index
end

---How much of the row each column gets. Declared `share`s are honoured like
---`hypr/scene/layout.lua`'s block shares; columns with no declared share
---split whatever is left evenly. One to three columns only — the desk is
---one row, never more (see docs/deck.md).
---@param columns Deck.Column[]
---@return number[] fraction per column, indexed like `columns`
local function fractions(columns)
  local declared, loose = 0, {}
  local out = {}
  for i, column in ipairs(columns) do
    if column.share then
      declared = declared + column.share
      out[i] = column.share
    else
      loose[#loose + 1] = i
    end
  end
  if #loose == 0 then
    if declared > 0 and math.abs(declared - 1) > 1e-9 then
      for i, value in ipairs(out) do
        out[i] = value / declared
      end
    end
    return out
  end
  local spare = math.max(1 - declared, 0)
  local each = spare / #loose
  for _, i in ipairs(loose) do
    out[i] = each
  end
  return out
end

---Place the visible member of every column and report the rest to hold.
---
---A column always shows exactly one window at full column height — never a
---partial window, never a shrink-to-fit split (unlike a `scene` block's
---stack, which divides its share among every member). Scrolling changes
---which window is visible, not how much of it shows.
---@param spec Deck.Spec
---@param tiles Scene.Tile[] tiled windows on the deck workspace
---@param area Scene.Area
---@param opts { gaps_in: number?, gaps_out: number?, scroll: table<integer, integer>?,
---order: table<integer, string[]>? }
---scroll: 1-based visible index per column order, from the persisted records
---(hypr/scene/deck_order.lua) the provider owns; nil/missing defaults to 1
---(the first window). `order`: the recorded address list per column (the
---same records' `order` field), which `stacks` leads with so a reload
---re-enumerating windows cannot scramble the strip.
---@return Scene.Box[] boxes one per visible tile
---@return string[] hold addresses of every non-visible deck member — the
---executor's cue to move them off the workspace (see module comment)
---What a tile belongs to on a strip: its DECLARED identity when one applies,
---the live Hyprland group otherwise.
---
---A declared group (`docs/declared-groups.md`) is one thing from its first
---window's first frame. Reading the live group instead made a project four
---separate things while its windows were still mapping, and the strip parked
---three of them before the group could form -- after which they could never
---join it, because a parked window must not be handed to `HL.Group`. Only a
---block that actually groups counts: a `group = false` block (the ad-hoc
---terminals) keeps one thing per window, as before.
---@param spec Scene.Spec
---@param tile Scene.Tile
---@return string?
function M.thing_key(spec, tile)
  for _, tag in ipairs(tile.tags or {}) do
    -- Hyprland renders a tag it applied itself with a trailing `*`.
    local scene, order = tag:match("^block:([^/]+)/(%d+)")
    if scene and order then
      for _, block in ipairs(spec.blocks or {}) do
        if block.group and tostring(block.order) == order then
          return ("block:%s/%s"):format(scene, order)
        end
      end
    end
  end
  return tile.group
end

function M.boxes(spec, tiles, area, opts)
  opts = opts or {}
  local gaps_in = opts.gaps_in or 0
  -- `gaps_out` is a CssGap just like the scene layout's: a bare number is
  -- uniform on all sides, a table names each side (LEO-421 follow-up). The
  -- deck used to force it to one symmetric number, which made asymmetric
  -- outer gaps (a tighter top for the bar, say) collapse to the left value
  -- on every other side.
  local top, right, bottom, left = layout.sides(opts.gaps_out)
  local scroll = opts.scroll or {}

  local columns = {}
  for _, c in ipairs(spec.columns) do
    columns[#columns + 1] = c
  end
  table.sort(columns, function(a, b)
    return a.order < b.order
  end)
  -- The physical constraint (docs/deck.md): one row, one to three columns.
  -- A declaration outside that bound is truncated rather than refused here —
  -- validation belongs to the editor/loader, not this arithmetic.
  while #columns > MAX_COLUMNS do
    columns[#columns] = nil
  end

  local stacks = M.stacks(spec, tiles, opts.order)
  local boxes, hold = {}, {}
  if #columns < MIN_COLUMNS then
    return boxes, hold
  end

  local inner_x = area.x + left
  local inner_y = area.y + top
  local inner_w = area.w - left - right
  local inner_h = area.h - top - bottom
  local usable = inner_w - gaps_in * (#columns - 1)

  local shares = fractions(columns)
  local cursor = inner_x
  for i, column in ipairs(columns) do
    local width = (i == #columns) and (inner_x + inner_w - cursor) or math.floor(usable * shares[i] + 0.5)
    local stack = stacks[column.order] or {}
    local representatives, members = layout.collapse_groups(stack, function(tile)
      return M.thing_key(spec, tile)
    end)
    local index = M.clamp_scroll(scroll[column.order], #representatives)
    for j, rep in ipairs(representatives) do
      if j == index then
        local group_members = members[M.thing_key(spec, rep)]
        if group_members then
          for _, member in ipairs(group_members) do
            boxes[#boxes + 1] = { address = member.address, x = cursor, y = inner_y, w = width, h = inner_h }
          end
        else
          boxes[#boxes + 1] = { address = rep.address, x = cursor, y = inner_y, w = width, h = inner_h }
        end
      else
        local group_members = members[M.thing_key(spec, rep)]
        if group_members then
          for _, member in ipairs(group_members) do
            hold[#hold + 1] = member.address
          end
        else
          hold[#hold + 1] = rep.address
        end
      end
    end
    cursor = cursor + width + gaps_in
  end
  return boxes, hold
end

---Every column's own box, keyed by `order`, regardless of whether it
---currently shows a tile. A column is a PLACE (`hypr/lib/dock.lua`'s
---`column:<order>` doc), so an area published for `hypr/lib/area.lua` needs
---its box even on an empty column — the same geometry `M.boxes` computes
---per visible member, minus the placement.
---@param spec Deck.Spec
---@param area Scene.Area
---@param opts { gaps_in: number?, gaps_out: (number|Scene.CssGap)? }
---@return table<integer, Scene.Box> boxes keyed by column order
function M.column_boxes(spec, area, opts)
  opts = opts or {}
  local gaps_in = opts.gaps_in or 0
  local top, right, bottom, left = layout.sides(opts.gaps_out)

  local columns = {}
  for _, c in ipairs(spec.columns) do
    columns[#columns + 1] = c
  end
  table.sort(columns, function(a, b)
    return a.order < b.order
  end)
  while #columns > MAX_COLUMNS do
    columns[#columns] = nil
  end
  if #columns < MIN_COLUMNS then
    return {}
  end

  local inner_x = area.x + left
  local inner_y = area.y + top
  local inner_w = area.w - left - right
  local inner_h = area.h - top - bottom
  local usable = inner_w - gaps_in * (#columns - 1)

  local shares = fractions(columns)
  local out = {}
  local cursor = inner_x
  for i, column in ipairs(columns) do
    local width = (i == #columns) and (inner_x + inner_w - cursor) or math.floor(usable * shares[i] + 0.5)
    out[column.order] = { x = cursor, y = inner_y, w = width, h = inner_h }
    cursor = cursor + width + gaps_in
  end
  return out
end

M.MIN_COLUMNS = MIN_COLUMNS
M.MAX_COLUMNS = MAX_COLUMNS

return M
