-- Pure decisions behind the scene-layout navigation binds (LEO-344): which
-- tile is "left"/"right", which window is next inside a tile, which monitor
-- is adjacent, and which workspace a workspace-row key names on a monitor.
--
-- No `hl` here. Bind handlers in `hypr/binds.lua` gather the live state
-- (focused window, monitor list, the applied desk) and hand it to these
-- functions; `tests/nav_spec.lua` drives them with fixtures instead of a
-- compositor.
local layout = require("hypr.scene.layout")

local M = {}

-- The workspace-row keysyms read as symbols, never digits, in which-key text
-- (LEO-344 decision comment + clarification): "plus" reads "+", and so on.
M.KEY_SYMBOLS = {
  plus = "+",
  bracketleft = "[",
  braceleft = "{",
  parenleft = "(",
  ampersand = "&",
  equal = "=",
  parenright = ")",
  braceright = "}",
  bracketright = "]",
  asterisk = "*",
}

---@param key string a `workspace_keys` entry, e.g. "bracketleft"
---@return string the symbol to show in which-key/descriptions, falling back
---to the raw key name for one this table does not know
function M.symbol_for(key)
  return M.KEY_SYMBOLS[key] or key
end

-- === Tile order ===

---@class Nav.Tile
---@field key string stable slot identity (`hypr/scene/layout.lua`'s `entry_key`)
---@field addresses string[] every window in this tile, left-to-right/top-to-bottom
---@field group boolean whether this tile is one Hyprland group

---A group's member addresses, the chosen entry address first (if it is
---actually one of `members`), the rest in arrival order behind it. `chosen`
---is the caller's policy decision — this function only places it; it has no
---opinion on how it was picked. `chosen == nil` (no policy applies: an
---untouched group, no adapter, nothing recorded yet) leaves arrival order
---untouched.
---@param members Scene.Tile[]
---@param chosen string?
---@return string[]
function M.group_entry_order(members, chosen)
  local out = {}
  if chosen then
    for _, m in ipairs(members) do
      if m.address == chosen then
        out[#out + 1] = m.address
      end
    end
  end
  for _, m in ipairs(members) do
    if m.address ~= chosen then
      out[#out + 1] = m.address
    end
  end
  return out
end

---The scene's tiles, left to right, in exactly the order
---`hypr/scene/layout.lua` places them (declared blocks by `order`, then
---strays in arrival order) — so `mod+h/l` always agrees with what is on
---screen. A group tile's `addresses` lead with `opts.enter`'s pick
---(`group_entry_order`), not just whichever member the compositor happened
---to list first, so crossing INTO a group tile lands on what the user was
---already looking at (LEO-380) — or arrival order when there is no `opts`,
---no `enter`, or `enter` returns nil (nothing to prefer).
---@param scene Scene.Spec
---@param tiles Scene.Tile[] tiled windows present on the scene's workspace
---@param opts { enter: (fun(members: Scene.Tile[], group_key: string): string?)? }?
---enter picks a group's entry member; the caller supplies the policy
---(`hypr/scene/group_adapters.lua`'s adapter registry) so this stays pure.
---@return Nav.Tile[]
function M.tile_order(scene, tiles, opts)
  local representatives, members = layout.collapse_groups(tiles)
  local sequenced = layout.sequence(scene, representatives)
  local out = {}
  for _, entry in ipairs(sequenced) do
    local addresses = {}
    if entry.tile.group and members[entry.tile.group] then
      local group_members = members[entry.tile.group]
      local chosen = opts and opts.enter and opts.enter(group_members, entry.tile.group)
      addresses = M.group_entry_order(group_members, chosen)
    else
      for _, tile in ipairs(entry.tiles) do
        addresses[#addresses + 1] = tile.address
      end
    end
    out[#out + 1] = {
      key = layout.entry_key(entry),
      addresses = addresses,
      group = entry.tile.group ~= nil,
    }
  end
  return out
end

---The index of the tile holding `address`, or nil if none does.
---@param tiles Nav.Tile[]
---@param address string
---@return integer?
function M.tile_index(tiles, address)
  for i, tile in ipairs(tiles) do
    for _, a in ipairs(tile.addresses) do
      if a == address then
        return i
      end
    end
  end
  return nil
end

---The neighbouring tile in `dir` ("left"|"right"), or nil at the edge — the
---caller's cue to continue onto the adjacent monitor.
---@param tiles Nav.Tile[]
---@param index integer
---@param dir "left"|"right"
---@return Nav.Tile?
function M.neighbor_tile(tiles, index, dir)
  local step = dir == "left" and -1 or 1
  return tiles[index + step]
end

---The tile nearest the edge a `dir` move crosses INTO on the next monitor:
---continuing right lands on its leftmost tile, continuing left on its
---rightmost — the "nearest-edge tile" the decision comment names.
---@param tiles Nav.Tile[]
---@param dir "left"|"right"
---@return Nav.Tile?
function M.edge_tile(tiles, dir)
  if #tiles == 0 then
    return nil
  end
  return dir == "left" and tiles[#tiles] or tiles[1]
end

---Swap two tiles' key order. Returns the full ordered key list (every
---tile's `key`, in the new order) for `hypr/scene/order.lua` to store; a
---missing neighbour (edge, no adjacent tile) is the caller's job to check
---before calling this.
---@param tiles Nav.Tile[]
---@param index integer
---@param dir "left"|"right"
---@return string[]? new_order, nil if there is no neighbour to swap with
function M.swap_order(tiles, index, dir)
  local other = index + (dir == "left" and -1 or 1)
  if not tiles[other] then
    return nil
  end
  local keys = {}
  for i, tile in ipairs(tiles) do
    keys[i] = tile.key
  end
  keys[index], keys[other] = keys[other], keys[index]
  return keys
end

-- === Window order within a tile ===

---The next/previous window address inside one tile's list — a group's
---members or a stacked block's windows. Does not wrap: at either end this
---returns nil, so the bind is a no-op rather than looping silently past a
---single window.
---@param addresses string[]
---@param current string
---@param dir "next"|"prev"
---@return string?
function M.window_neighbor(addresses, current, dir)
  for i, address in ipairs(addresses) do
    if address == current then
      local target = i + (dir == "next" and 1 or -1)
      return addresses[target]
    end
  end
  return nil
end

-- === mod+h/l decision (LEO-380) ===

---@class Nav.Action
---@field kind "window"|"monitor"|"none"
---@field address string? present when kind == "window"
---@field name string? present when kind == "monitor"

---One `mod+h`/`mod+l` press, decided in full: move across tiles in scene
---order (a group is one tile); at the edge, or from an empty workspace (no
---`active` window), cross to the adjacent non-ignored monitor; landing there
---focuses its edge tile, or the monitor itself when that side has none
---(`target` omitted or empty) — so the opposite key always returns, since
---focusing a monitor still lets its own tile lookup find the window next
---time.
---@param ctx {
---monitors: { name: string, x: number }[],
---ignored: string[]?,
---focused: string?,
---tiles: Nav.Tile[],
---active: string?,
---dir: "left"|"right",
---target: { tiles: Nav.Tile[] }?}
---@return Nav.Action
function M.decide(ctx)
  local index = ctx.active and M.tile_index(ctx.tiles, ctx.active) or nil
  if index then
    local neighbor = M.neighbor_tile(ctx.tiles, index, ctx.dir)
    if neighbor then
      return { kind = "window", address = neighbor.addresses[1] }
    end
  end

  -- Empty workspace, focused window not in the tile list, or the tile-order
  -- edge: cross to the adjacent usable monitor.
  if not ctx.focused then
    return { kind = "none" }
  end
  local ordered = M.monitor_order(M.usable_monitors(ctx.monitors, ctx.ignored))
  local adjacent = M.adjacent_monitor(ordered, ctx.focused, ctx.dir)
  if not adjacent then
    return { kind = "none" }
  end

  local target_tiles = ctx.target and ctx.target.tiles
  local edge = target_tiles and #target_tiles > 0 and M.edge_tile(target_tiles, ctx.dir)
  if edge then
    return { kind = "window", address = edge.addresses[1] }
  end
  return { kind = "monitor", name = adjacent.name }
end

-- === Monitors ===

---Monitors left to right, by their reported `x`. Ties keep their original
---relative order (stable sort).
---@param monitors { name: string, x: number }[]
---@return { name: string, x: number }[]
function M.monitor_order(monitors)
  local indexed = {}
  for i, m in ipairs(monitors) do
    indexed[i] = { m = m, i = i }
  end
  table.sort(indexed, function(a, b)
    if a.m.x == b.m.x then
      return a.i < b.i
    end
    return a.m.x < b.m.x
  end)
  local out = {}
  for i, entry in ipairs(indexed) do
    out[i] = entry.m
  end
  return out
end

---Whether a directional-focus dispatch actually moved focus, by comparing
---the active window's address before and after it ran. False (unchanged, or
---gone) is the caller's cue to cross to the adjacent monitor instead — the
---layout's own `focus_left`/`focus_right` silently does nothing when there is
---no window that way, which off a scene workspace otherwise strands focus at
---a monitor edge (LEO-372).
---@param before string?
---@param after string?
---@return boolean
function M.focus_unchanged(before, after)
  return before == after
end

---The monitor adjacent to `name` in `dir`, or nil at the outer edge.
---@param ordered { name: string }[] from `monitor_order`
---@param name string
---@param dir "left"|"right"
---@return { name: string }?
function M.adjacent_monitor(ordered, name, dir)
  for i, m in ipairs(ordered) do
    if m.name == name then
      return ordered[i + (dir == "left" and -1 or 1)]
    end
  end
  return nil
end

---Whether `name` is one of the host's ignored monitors (`ignored_monitors`
---in `conf/hosts/*.lua`): an output that is connected but never a target.
---@param ignored string[]?
---@param name string?
---@return boolean
function M.is_ignored(ignored, name)
  for _, other in ipairs(ignored or {}) do
    if other == name then
      return true
    end
  end
  return false
end

---Monitors minus the ignored ones, order kept.
---@generic T: { name: string }
---@param monitors T[]
---@param ignored string[]?
---@return T[]
function M.usable_monitors(monitors, ignored)
  local out = {}
  for _, m in ipairs(monitors or {}) do
    if not M.is_ignored(ignored, m.name) then
      out[#out + 1] = m
    end
  end
  return out
end

---The monitor an action should target instead of `name`: the primary when
---`name` is ignored (or unknown), `name` itself otherwise.
---@param ignored string[]?
---@param name string?
---@param primary string?
---@return string?
function M.target_monitor(ignored, name, primary)
  if name == nil or M.is_ignored(ignored, name) then
    return primary
  end
  return name
end

---What keeps the desk off ignored monitors, as dispatch-shaped actions:
---
---  * `{ show = "<special name without prefix>" }` for a special shown on an
---    ignored monitor: focus the primary, then toggle it there
---  * `{ move = address, workspace = name }` for `w` standing on a plain
---    workspace of an ignored monitor: sent to the primary's active workspace
---
---A special that is not shown (a silently routed shelf) is left alone; the
---shelf key opens it on a usable monitor.
---@param ignored string[]?
---@param primary string?
---@param monitors table[] `hl.get_monitors()`
---@param w table? the window an event carried, if any
---@return table[] actions
function M.off_ignored(ignored, primary, monitors, w)
  local actions = {}
  if not primary or #(ignored or {}) == 0 then
    return actions
  end
  local primary_workspace
  for _, m in ipairs(monitors or {}) do
    if m.name == primary and m.activeWorkspace then
      primary_workspace = m.activeWorkspace.name
    end
  end
  for _, m in ipairs(monitors or {}) do
    local special = m.specialWorkspace and m.specialWorkspace.name
    if M.is_ignored(ignored, m.name) and special and special ~= "" then
      actions[#actions + 1] = { show = (string.gsub(special, "^special:", "")) }
    end
  end
  local ws = w and w.workspace
  local on = ws and ws.monitor and ws.monitor.name
  if ws and M.is_ignored(ignored, on) and not tostring(ws.name):find("^special:") and primary_workspace then
    actions[#actions + 1] = { move = w.address, workspace = primary_workspace }
  end
  return actions
end

-- === Workspace row: Nth scene on the focused monitor ===

---The active mode's scenes placed on one monitor output, in desk order.
---@param desk_scenes { name: string, output: string? }[] resolved placements
---(scene name + the output its monitor role resolved to — see
---`hypr/hyprfocus/init.lua` `M.place`/`output_for`)
---@param output string the focused monitor's output name
---@return string[] scene names, in the order the desk lists them
function M.workspaces_on_monitor(desk_scenes, output)
  local out = {}
  for _, placement in ipairs(desk_scenes) do
    if placement.output == output then
      out[#out + 1] = placement.name
    end
  end
  return out
end

---The Nth workspace name for a `mod+<key>` press, or nil when the monitor
---has fewer scenes than the key's position — the no-op that keeps an
---unreachable key from doing anything (AGENTS.md: never show or run a
---binding that cannot execute).
---@param names string[] from `workspaces_on_monitor`
---@param n integer 1-based position in `workspace_keys`
---@return string?
function M.nth_workspace(names, n)
  return names[n]
end

---The workspace a `mod+TAB` (`dir` "next") or `mod+shift+TAB` ("prev")
---press lands on: the neighbour of `current` in `names`, wrapping at both
---ends. A current workspace outside the list (a special, a stray numbered
---one) enters at the first ("next") or last ("prev") name. Nil when there is
---nothing to go to: an empty list, or `current` the only name.
---@param names string[] from `workspaces_on_monitor`
---@param current string?
---@param dir "next"|"prev"
---@return string?
function M.cycle_workspace(names, current, dir)
  local count = #names
  if count == 0 then
    return nil
  end
  for i, name in ipairs(names) do
    if name == current then
      if count == 1 then
        return nil
      end
      local step = dir == "prev" and -1 or 1
      return names[(i - 1 + step) % count + 1]
    end
  end
  return dir == "prev" and names[count] or names[1]
end

return M
