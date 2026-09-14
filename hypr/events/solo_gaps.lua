-- Wide gaps for a workspace holding one tile.
--
-- The scrolling layout gives a lone window a column and leaves the rest of the
-- panel empty, which is the point of it. dwindle and master cannot: one window
-- means one tile, and one tile means the whole monitor. This closes that gap by
-- growing the outer gap instead, so a single tile is framed on every layout
-- rather than only on the one that was built for it.
--
-- "Tile" is the layout's unit, not the window's: a Hyprland group (the Dofus
-- clients, windowrules.lua) is one node in the layout tree, so a workspace
-- holding only the group deserves the same framing as one holding only a lone
-- window (LEO-191). Each group counts once, and every ungrouped tiled window
-- once.
--
-- Workspace rules own gaps per workspace (see hyprland.lua's gaps_by_monitor),
-- so this rewrites the rule rather than the global: a workspace keeps whatever
-- it was given the moment a second tile arrives.
--
-- A workspace opts out of the framing in its spec (engine.solo_gaps = "none").
-- Earlier this was inferred from `gaps_out == 0`, but a sentinel that happens
-- to equal "asked for no gaps" is not policy — LEO-190/191 made the decision
-- part of the spec.

-- Layouts that already frame a lone window on their own.
local self_framing = { scrolling = true }

-- What a solo tile is worth, on top of the workspace's own outer gap. Enough
-- to read as deliberate on a 5120px panel without stranding the window.
local SOLO_EXTRA = 180

-- workspace id -> the gaps_out it had before we widened it, so the original
-- value is restored rather than recomputed. nil means "not currently widened".
---@type table<integer, integer|table>
local original = {}

-- The declared opt-out: `engine.solo_gaps = "none"` in a workspace spec means
-- the workspace's gaps are never rewritten. Everything else participates.
---@param spec table|nil
---@return boolean
local function opts_out(spec)
  local engine = spec and spec.engine
  return engine ~= nil and engine.solo_gaps == "none"
end

---The spec a workspace was configured with, or nil for one the host never named
---(a scratch workspace, or a special that only exists while it is open).
---@param id integer
---@return table|nil
local function spec_for(id)
  for _, spec in ipairs(config.host.workspaces.workspace_specs) do
    if tostring(spec.workspace) == tostring(id) then
      return spec
    end
  end
  return nil
end

---Counts tiled tiles on a workspace. A group holds many windows but occupies
---one node in the layout tree, so it counts as one tile; floating windows take
---no tile, so they neither trigger the wide gap nor cancel it.
---@param id integer
---@return integer
local function tile_count(id)
  local tiles, groups = 0, {}
  for _, w in ipairs(hl.get_windows() or {}) do
    if w.workspace and w.workspace.id == id and not w.floating then
      if w.group ~= nil then
        groups[tostring(w.group)] = true
      else
        tiles = tiles + 1
      end
    end
  end
  for _ in pairs(groups) do
    tiles = tiles + 1
  end
  return tiles
end

---Adds `extra` to every edge of a gap value, keeping its shape.
---@param gaps integer|table
---@param extra integer
---@return integer|table
local function widen(gaps, extra)
  if type(gaps) ~= "table" then
    return (tonumber(gaps) or 0) + extra
  end
  local out = {}
  for edge, value in pairs(gaps) do
    out[edge] = value + extra
  end
  return out
end

---@param id integer
---@param gaps_out integer|table
local function set_gaps(id, gaps_out)
  hl.workspace_rule({ workspace = tostring(id), gaps_out = gaps_out })
end

---Widens or restores a workspace's outer gap to match how many tiles it holds.
---@param ws table|nil Hyprland workspace, as reported by the event
local function apply(ws)
  if not ws or not ws.id then
    return
  end

  local spec = spec_for(ws.id)
  if opts_out(spec) then
    return
  end
  if self_framing[ws.tiled_layout] then
    return
  end

  -- gaps_out is a CssGap: an integer, or a table of named edges. Widening has to
  -- preserve the shape, because the top edge is deliberately tighter than the
  -- others (the bar reserves its own height, see conf.lua) and flattening it to
  -- one number would put the canyon back.
  local base = (spec and spec.gaps_out) or hl.get_config("general.gaps_out") or 0

  if tile_count(ws.id) == 1 then
    if original[ws.id] == nil then
      original[ws.id] = base
      set_gaps(ws.id, widen(base, SOLO_EXTRA))
    end
  elseif original[ws.id] ~= nil then
    set_gaps(ws.id, original[ws.id])
    original[ws.id] = nil
  end
end

local function apply_active()
  apply(hl.get_active_workspace())
end

hl.on("workspace.active", apply_active)
hl.on("window.open_early", apply_active)
