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
---@return Dock.Edge? edge, ("x"|"y")? axis, ("start"|"center"|"end")? align, string? other_edge
local function dominant(vword, hword)
  local v_edge = vword == "top" or vword == "bottom"
  local h_edge = hword == "left" or hword == "right"
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

---The region/anchor/grow for one resolved edge dock: the gutter between
---`target`'s edge and the monitor's own, minus `standoff` (the scene's
---`gaps_in`, kept clear next to the window). The region spans the target's
---full length on that edge; `align` places the anchor point — the corner
---touching the window, which is where the isle grows away from — within it.
---@param edge Dock.Edge
---@param target Dock.Box
---@param monitor Dock.Box
---@param standoff number
---@param align "start"|"center"|"end"
---@param gaps_out table<Dock.Edge, number>
---@return Dock.Box region, { x: number, y: number } anchor, "up"|"down"|"left"|"right" grow
local function edge_geometry(edge, target, monitor, standoff, align, gaps_out)
  local thickness = math.max((gaps_out[edge] or 0) - standoff, 0)
  local region, anchor, grow, cross_origin, cross_size, cross_is_x

  if edge == "top" then
    region = { x = target.x, y = monitor.y, w = target.w, h = thickness }
    anchor = { x = target.x, y = target.y - standoff }
    grow, cross_origin, cross_size, cross_is_x = "up", target.x, target.w, true
  elseif edge == "bottom" then
    local y = target.y + target.h + standoff
    region = { x = target.x, y = y, w = target.w, h = thickness }
    anchor = { x = target.x, y = y }
    grow, cross_origin, cross_size, cross_is_x = "down", target.x, target.w, true
  elseif edge == "left" then
    region = { x = monitor.x, y = target.y, w = thickness, h = target.h }
    anchor = { x = target.x - standoff, y = target.y }
    grow, cross_origin, cross_size, cross_is_x = "left", target.y, target.h, false
  else -- right
    local x = target.x + target.w + standoff
    region = { x = x, y = target.y, w = thickness, h = target.h }
    anchor = { x = x, y = target.y }
    grow, cross_origin, cross_size, cross_is_x = "right", target.y, target.h, false
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
---@param of string
---@param ctx { monitor: Dock.Box, targets: table<string, Dock.Box> }
---@return Dock.Box? box, boolean is_screen
local function target_box(of, ctx)
  if of == "screen" then
    return ctx.monitor, true
  end
  return ctx.targets[of], false
end

---Resolve one dock-spec chain level. `stepped_down` is true once resolution
---has left the isle's own first-choice spec (a declared `fallback`, or the
---ladder's implicit "same anchor on screen"), which is what separates
---`"docked"` from `"fallback"` in the published state.
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
  ---entry resolved to is already claimed. All three collapse the same way.
  local function step_down()
    if entry.fallback ~= nil then
      return resolve_chain(entry.fallback, ctx, claimed, true)
    end
    if entry.of == "screen" then
      -- Already the ladder's last rung and it still failed (a claimed
      -- region with nothing left to try) -- nothing further to collapse to.
      return nil
    end
    return resolve_chain({ at = entry.at, of = "screen", orientation = entry.orientation }, ctx, claimed, true)
  end

  local target, is_screen = target_box(entry.of, ctx)
  if not target then
    return step_down()
  end

  local words = M.ANCHOR_WORDS[entry.at]
  -- `dominant` also reports the axis it resolved on; nothing downstream needs
  -- it, since the edge already carries the direction.
  local edge, _, align, other_edge = dominant(words[1], words[2])

  local resolved_edge, resolved_align = edge, align
  if edge and not is_screen and inter_window(edge, target, ctx.boxes) then
    resolved_edge = nil
    if other_edge then
      local switched_align = words[1] == "top" and "start" or "end"
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
    region, anchor, grow =
      edge_geometry(resolved_edge, target, ctx.monitor, standoff, resolved_align, ctx.gaps_out or {})
  else
    -- Pure center: no gutter to grow into, so the isle rests on the
    -- target's own box (screen for a HUD-style center dock).
    region = { x = target.x, y = target.y, w = target.w, h = target.h }
    anchor = { x = target.x + target.w / 2, y = target.y + target.h / 2 }
    grow = "down"
  end

  local region_key = entry.of .. "@" .. (resolved_edge or "center")
  if claimed[region_key] then
    return step_down()
  end
  claimed[region_key] = true

  return {
    region = region,
    anchor = anchor,
    grow = grow,
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
