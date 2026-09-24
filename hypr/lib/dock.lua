-- Dock grammar resolution: where a quickshell isle sits, as arithmetic.
--
-- Pure, same discipline as hypr/scene/layout.lua: a scene's `docks`
-- declaration, the scene's own placed tile boxes, the monitor box and the
-- resolved four-sided gaps go in; a box/anchor/grow per isle comes out. No
-- `hl`, no store, no dispatch — the three publish points (conf/host.lua,
-- hypr/scene/spec.lua, hypr/scene/provider.lua) call this and write the
-- result themselves.
--
-- See docs/scenes.md's "Docks" section for the grammar this implements.
local M = {}

---@class Dock.Box
---@field x number
---@field y number
---@field w number
---@field h number

---@alias Dock.Edge "top"|"right"|"bottom"|"left"

---@class Dock.Spec
---@field at string one of the nine-grid anchors below
---@field of string "screen" | "block:<order>" | "slot:<slot>" | "class:<class>"
---@field orientation ("horizontal"|"vertical")? overrides the edge default
---@field fallback (Dock.Spec|false)? a dock spec of the same shape, chainable

---@class Dock.Published
---@field region Dock.Box?
---@field anchor { x: number, y: number }?
---@field grow ("up"|"down"|"left"|"right")?
---@field edge Dock.Edge? the gutter the isle stands in
---@field align ("start"|"center"|"end")? where the anchor sits ALONG the edge
---@field orientation ("horizontal"|"vertical")?
---@field state "docked"|"fallback"|"resting"|"hidden"

-- The nine-grid, spelled exactly as scenes declare it -> {vertical word,
-- horizontal word}. `center` is the one cell with no hyphen (the middle of
-- the middle row), spelled bare rather than "middle-center".
M.ANCHOR_WORDS = {
  ["top-left"] = { "top", "left" },
  ["top-center"] = { "top", "center" },
  ["top-right"] = { "top", "right" },
  ["middle-left"] = { "middle", "left" },
  ["center"] = { "middle", "center" },
  ["middle-right"] = { "middle", "right" },
  ["bottom-left"] = { "bottom", "left" },
  ["bottom-center"] = { "bottom", "center" },
  ["bottom-right"] = { "bottom", "right" },
  -- Mirrored corners: the SIDE gutter, aligned to one end of that edge. The
  -- nine-grid alone cannot say "in the left gutter, at the bottom" -- its
  -- corners always lead with the vertical word -- and that is a position a
  -- scene genuinely wants (a vertical isle standing in the left gutter,
  -- bottom-aligned). Leading with the horizontal word says it.
  ["left-top"] = { "top", "left", "h" },
  ["left-bottom"] = { "bottom", "left", "h" },
  ["right-top"] = { "top", "right", "h" },
  ["right-bottom"] = { "bottom", "right", "h" },
}

---Whether `of` is one of the four grammars a dock target may name.
---@param of unknown
---@return boolean
function M.valid_of(of)
  if type(of) ~= "string" then
    return false
  end
  return of == "screen"
    or of:match("^block:%d+$") ~= nil
    or of:match("^slot:.+$") ~= nil
    or of:match("^class:.+$") ~= nil
end

---Whether `spec` is a well-formed dock entry at one chain level (its own
---`fallback`, if any, is validated recursively by the caller). `false` (the
---scene withholding the isle) is handled by the caller, not here.
---@param spec unknown
---@return boolean
function M.valid_entry(spec)
  return type(spec) == "table"
    and type(spec.at) == "string"
    and M.ANCHOR_WORDS[spec.at] ~= nil
    and M.valid_of(spec.of)
    and (spec.orientation == nil or spec.orientation == "horizontal" or spec.orientation == "vertical")
end

---Given the vertical/horizontal words of an anchor, the dominant edge, the
---cross axis it aligns along, and the alignment on that axis.
---
---A corner anchor (both words name an edge: top-left, bottom-right, ...)
---leads with the vertical word (`docs/scenes.md`: "dominant axis is the
---first word") and remembers the horizontal word as the corner's other edge,
---for the inter-window axis switch below. An edge-only anchor (top-center,
---middle-left) has exactly one word that names an edge; that one is
---dominant, the other is pure alignment.
---@param vword string
---@param hword string
---@param lead string? "h" when the anchor led with its horizontal word
---@return Dock.Edge? edge, ("x"|"y")? axis, ("start"|"center"|"end")? align, string? other_edge
local function dominant(vword, hword, lead)
  local v_edge = vword == "top" or vword == "bottom"
  local h_edge = hword == "left" or hword == "right"
  if lead == "h" and h_edge and v_edge then
    -- The side gutter is the dominant one, and the vertical word aligns the
    -- isle along it; the vertical edge stays as the switch's other candidate.
    return hword, "y", (vword == "top" and "start" or "end"), vword
  end
  if v_edge and h_edge then
    return vword, "x", (hword == "left" and "start" or "end"), hword
  elseif v_edge then
    return vword, "x", (hword == "center" and "center" or (hword == "left" and "start" or "end")), nil
  elseif h_edge then
    return hword, "y", (vword == "middle" and "center" or (vword == "top" and "start" or "end")), nil
  end
  return nil, nil, nil, nil
end

---Two ranges [a0,a1) and [b0,b1) overlap.
local function overlaps(a0, a1, b0, b1)
  return a0 < b1 and b0 < a1
end

---Two boxes are the same tile, by value: the target box handed to us by the
---caller and one entry of the full placed-box list are not always the same
---table instance.
local function same_box(a, b)
  return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

---Whether `edge` of `target` is bounded by another placed tile rather than
---the screen — the gutter rule's "never between two windows". Only tiles
---strictly further out, overlapping the target's span on the cross axis,
---count.
---@param edge Dock.Edge
---@param target Dock.Box
---@param boxes Dock.Box[] every tile placed on the scene, target included
---@return boolean
local function inter_window(edge, target, boxes)
  for _, b in ipairs(boxes or {}) do
    if not same_box(b, target) then
      if edge == "top" and b.y < target.y and overlaps(b.x, b.x + b.w, target.x, target.x + target.w) then
        return true
      elseif edge == "bottom" and b.y > target.y and overlaps(b.x, b.x + b.w, target.x, target.x + target.w) then
        return true
      elseif edge == "left" and b.x < target.x and overlaps(b.y, b.y + b.h, target.y, target.y + target.h) then
        return true
      elseif edge == "right" and b.x > target.x and overlaps(b.y, b.y + b.h, target.y, target.y + target.h) then
        return true
      end
    end
  end
  return false
end

---An edge's default orientation (docs/scenes.md): left/right gutters run
---vertically, top/bottom run horizontally; a pure-center dock (no edge) has
---nothing to default from and reads as horizontal.
---@param edge Dock.Edge?
---@return "horizontal"|"vertical"
local function default_orientation(edge)
  if edge == "left" or edge == "right" then
    return "vertical"
  end
  return "horizontal"
end

---The region/anchor/grow for one resolved edge dock.
---
---The gutter is the band between the monitor's edge and the target's, and
---the pass that calls this holds both boxes — so the band is MEASURED, never
---re-derived from the gap ladder, whose answer is not the geometry the
---compositor actually tiled (the two were ~14px apart on a real desk, and
---the isles sat exactly that far off).
---
---A WINDOW target is hugged (docs/scenes.md): the isle's growth corner sits
---on the target's edge, less `standoff` (the scene's `gaps_in`), and grows
---AWAY from the window into the gutter. So the isle follows its block on
---both axes — a scene with a deeper top gap carries the isle down with it,
---which standing every isle on the screen edge instead could never do.
---
---A SCREEN target uses the monitor minus the outer gap as a virtual window,
---so a fallback dock hugs the inner edge of the gap and grows into the gap
---rather than sitting hard against the screen edge.
---@param edge Dock.Edge
---@param target Dock.Box
---@param monitor Dock.Box
---@param standoff number the scene's `gaps_in`, spent between isle and window
---@param align "start"|"center"|"end"
---@param is_screen boolean the target IS the monitor
---@return Dock.Box region, { x: number, y: number } anchor, "up"|"down"|"left"|"right" grow
local function edge_geometry(edge, target, monitor, standoff, align)
  local region, anchor, grow, cross_origin, cross_size, cross_is_x

  if edge == "top" then
    -- The gutter reaches from the screen edge to the target's edge; the isle
    -- hugs the target and grows away from it (up into the gap). A screen target
    -- uses the same model, with the content area as the virtual window.
    local inner = target.y
    region = { x = target.x, y = monitor.y, w = target.w, h = math.max(inner - monitor.y, 0) }
    anchor = { x = target.x, y = inner - standoff }
    grow = "up"
    cross_origin, cross_size, cross_is_x = target.x, target.w, true
  elseif edge == "bottom" then
    local edge_y = monitor.y + monitor.h
    local inner = target.y + target.h
    region = { x = target.x, y = inner, w = target.w, h = math.max(edge_y - inner, 0) }
    anchor = { x = target.x, y = inner + standoff }
    grow = "down"
    cross_origin, cross_size, cross_is_x = target.x, target.w, true
  elseif edge == "left" then
    local inner = target.x
    region = { x = monitor.x, y = target.y, w = math.max(inner - monitor.x, 0), h = target.h }
    anchor = { x = inner - standoff, y = target.y }
    grow = "left"
    cross_origin, cross_size, cross_is_x = target.y, target.h, false
  else -- right
    local edge_x = monitor.x + monitor.w
    local inner = target.x + target.w
    region = { x = inner, y = target.y, w = math.max(edge_x - inner, 0), h = target.h }
    anchor = { x = inner + standoff, y = target.y }
    grow = "right"
    cross_origin, cross_size, cross_is_x = target.y, target.h, false
  end

  local point
  if align == "start" then
    point = cross_origin
  elseif align == "center" then
    point = cross_origin + cross_size / 2
  else
    point = cross_origin + cross_size
  end
  if cross_is_x then
    anchor.x = point
  else
    anchor.y = point
  end
  return region, anchor, grow
end

---The box a dock's `of` names, or nil when it names a tile that is not
---placed right now (an absent block/slot/class — collapse territory).
---A `screen` target is the monitor minus the scene's outer gap, so a fallback
---dock with no window still sits inside the gap rather than hard against the
---screen edge.
---@param of string
---@param ctx { monitor: Dock.Box, targets: table<string, Dock.Box>, gaps_out: table<Dock.Edge, number> }
---@return Dock.Box? box, boolean is_screen
local function target_box(of, ctx)
  if of == "screen" then
    local g = ctx.gaps_out or {}
    local left = g.left or 0
    local top = g.top or 0
    local right = g.right or 0
    local bottom = g.bottom or 0
    return {
      x = ctx.monitor.x + left,
      y = ctx.monitor.y + top,
      w = ctx.monitor.w - left - right,
      h = ctx.monitor.h - top - bottom,
    },
      true
  end
  return ctx.targets[of], false
end

---Resolve one dock-spec chain level. `stepped_down` is true once resolution
---has left the isle's own first-choice spec (a declared `fallback`), which is
---what separates `"docked"` from `"fallback"` in the published state.
---
---The ladder has exactly two rungs: the isle's own declaration (its target,
---then any declared `fallback` chain), then resting. There is no implicit
---"same anchor on screen" rung — an isle only ever deviates from resting
---through its own declaration, so two isles on one workspace cannot end up in
---different failure modes (one hugging a window gutter, one squeezed into the
---screen gap).
---@param entry Dock.Spec|false|nil
---@param ctx table
---@param claimed table<string, boolean>
---@param stepped_down boolean
---@return Dock.Published?
local function resolve_chain(entry, ctx, claimed, stepped_down)
  if not M.valid_entry(entry) then
    if type(entry) == "table" and entry.fallback ~= nil then
      return resolve_chain(entry.fallback, ctx, claimed, true)
    end
    return nil
  end

  ---A step-down that still needs to happen once we know why: the target is
  ---absent, both candidate gutters are inter-window, or the region this
  ---entry resolved to is already claimed. All three collapse the same way:
  ---down the declared fallback chain, or to rest.
  local function step_down()
    if entry.fallback ~= nil then
      return resolve_chain(entry.fallback, ctx, claimed, true)
    end
    return nil
  end

  local target, is_screen = target_box(entry.of, ctx)
  if not target then
    return step_down()
  end

  local words = M.ANCHOR_WORDS[entry.at]
  -- `dominant` also reports the axis it resolved on; nothing downstream needs
  -- it, since the edge already carries the direction.
  local edge, _, align, other_edge = dominant(words[1], words[2], words[3])

  local resolved_edge, resolved_align = edge, align
  if edge and not is_screen and inter_window(edge, target, ctx.boxes) then
    resolved_edge = nil
    if other_edge then
      -- Switching axis re-reads the anchor's own words: the alignment that
      -- applied along the refused edge is not the one the other edge takes.
      local switched_align = (words[3] == "h") and (words[2] == "left" and "start" or "end")
        or (words[1] == "top" and "start" or "end")
      if not inter_window(other_edge, target, ctx.boxes) then
        resolved_edge, resolved_align = other_edge, switched_align
      end
    end
    if not resolved_edge then
      return step_down()
    end
  end

  local standoff = is_screen and 0 or (ctx.gaps_in or 0)
  local region, anchor, grow
  if resolved_edge then
    -- A window target is hugged: the growth corner sits on the window's
    -- edge, less the scene's `gaps_in`, and the isle grows away from it into
    -- the gutter -- so the isle follows its block down a deeper gap instead
    -- of staying pinned to the screen edge on every scene. A `screen` target
    -- hugs the monitor-minus-gap box the same way, with no standoff.
    region, anchor, grow = edge_geometry(resolved_edge, target, ctx.monitor, standoff, resolved_align)
  else
    -- Pure center: no gutter to grow into, so the isle rests on the
    -- target's own box (screen for a HUD-style center dock).
    region = { x = target.x, y = target.y, w = target.w, h = target.h }
    anchor = { x = target.x + target.w / 2, y = target.y + target.h / 2 }
    grow = "down"
  end

  -- What a second isle may not take is the same SPOT, not the same gutter.
  -- A top gutter with one isle at its left end and another at its right is
  -- the shape every scene declares (`bar.center` left of `bar.clock`, both
  -- on the same block's top edge); keying the claim on the gutter alone
  -- refused the second one and sent it down the ladder every time. The
  -- alignment is what separates two isles sharing an edge, so it belongs in
  -- the key.
  local region_key = entry.of .. "@" .. (resolved_edge or "center") .. "@" .. (resolved_align or "center")
  if claimed[region_key] then
    return step_down()
  end
  claimed[region_key] = true

  return {
    region = region,
    anchor = anchor,
    grow = grow,
    -- Which SIDE of the isle the anchor point is. `grow` alone cannot say:
    -- it names the axis the isle extends along, and for a top gutter that
    -- leaves the anchor free to be the isle's left edge (`top-left`), its
    -- centre (`top-center`) or its right edge (`top-right`). Publishing only
    -- the point meant the consumer read every anchor as a left edge, so a
    -- right-aligned isle started where it should have ended and was shoved
    -- to the screen edge by the bounds clamp.
    align = resolved_align or "center",
    -- Which gutter this is. The consumer needs it to know which END of the
    -- region the window stands at, and neither `grow` nor `anchor` can say:
    -- a hugged window dock and an inward `screen` dock on the same edge grow
    -- in opposite directions. An isle too big for its gutter is pinned by
    -- the edge it must not cover, which is that end.
    edge = resolved_edge,
    orientation = entry.orientation or default_orientation(resolved_edge),
    state = stepped_down and "fallback" or "docked",
  }
end

---Resolve every isle a scene declares.
---
---@param docks table<string, Dock.Spec|false>? the scene's `docks` map
---@param ctx {
---  monitor: Dock.Box,
---  targets: table<string, Dock.Box>,     -- "block:1", "slot:x", "class:Y" -> placed box
---  boxes: Dock.Box[],                    -- every tile placed on the scene, for the gutter check
---  gaps_out: table<Dock.Edge, number>,   -- the scene's resolved four-sided gaps
---  gaps_in: number,                      -- the scene's standoff from a window
--- }
---@return table<string, Dock.Published>
function M.resolve(docks, ctx)
  ctx = ctx or {}
  ctx.monitor = ctx.monitor or { x = 0, y = 0, w = 0, h = 0 }
  ctx.targets = ctx.targets or {}
  ctx.boxes = ctx.boxes or {}
  ctx.gaps_out = ctx.gaps_out or {}
  ctx.gaps_in = ctx.gaps_in or 0

  local claimed = {}
  local out = {}

  -- A Lua table (and the JSON it round-trips through) carries no key order,
  -- so "declaration order" for conflict resolution is the one order that IS
  -- deterministic here: the isle id, sorted.
  local ids = {}
  for id in pairs(docks or {}) do
    ids[#ids + 1] = id
  end
  table.sort(ids)

  for _, id in ipairs(ids) do
    local spec = docks[id]
    if spec == false then
      out[id] = { state = "hidden" }
    else
      out[id] = resolve_chain(spec, ctx, claimed, false) or { state = "resting" }
    end
  end
  return out
end

return M
