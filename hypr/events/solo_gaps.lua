-- Wide gaps for a workspace holding one window.
--
-- The scrolling layout gives a lone window a column and leaves the rest of the
-- panel empty, which is the point of it. dwindle and master cannot: one window
-- means one tile, and one tile means the whole monitor. This closes that gap by
-- growing the outer gap instead, so a single window is framed on every layout
-- rather than only on the one that was built for it.
--
-- Workspace rules own gaps per workspace (see hyprland.lua's gaps_by_monitor),
-- so this rewrites the rule rather than the global: a workspace keeps whatever
-- it was given the moment a second window arrives.

-- Layouts that already frame a lone window on their own.
local self_framing = { scrolling = true }

-- What a solo window is worth, on top of the workspace's own outer gap. Enough
-- to read as deliberate on a 5120px panel without stranding the window.
local SOLO_EXTRA = 180

-- workspace id -> the gaps_out it had before we widened it, so the original
-- value is restored rather than recomputed. nil means "not currently widened".
---@type table<integer, integer>
local original = {}

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

---Counts tiled windows on a workspace. Floating windows do not take a tile, so
---they neither trigger the wide gap nor cancel it.
---@param id integer
---@return integer
local function tiled_count(id)
  local n = 0
  for _, w in ipairs(hl.get_windows() or {}) do
    if w.workspace and w.workspace.id == id and not w.floating then
      n = n + 1
    end
  end
  return n
end

---@param id integer
---@param gaps_out integer
local function set_gaps(id, gaps_out)
  hl.workspace_rule({ workspace = tostring(id), gaps_out = gaps_out })
end

---Widens or restores a workspace's outer gap to match how many windows it holds.
---@param ws table|nil Hyprland workspace, as reported by the event
local function apply(ws)
  if not ws or not ws.id then
    return
  end

  local spec = spec_for(ws.id)
  -- A workspace that asked for no gaps means it: the gaming workspace runs eight
  -- clients edge to edge, and framing one of them would be actively wrong.
  if spec and spec.gaps_out == 0 then
    return
  end
  if self_framing[ws.tiled_layout] then
    return
  end

  local base = (spec and spec.gaps_out) or hl.get_config("general.gaps_out") or 0
  if type(base) ~= "number" then
    base = 0
  end

  if tiled_count(ws.id) == 1 then
    if not original[ws.id] then
      original[ws.id] = base
      set_gaps(ws.id, base + SOLO_EXTRA)
    end
  elseif original[ws.id] then
    set_gaps(ws.id, original[ws.id])
    original[ws.id] = nil
  end
end

local function apply_active()
  apply(hl.get_active_workspace())
end

hl.on("workspace.active", apply_active)
hl.on("window.open_early", apply_active)
