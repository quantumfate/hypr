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

---The scene's tiles, left to right, in exactly the order
---`hypr/scene/layout.lua` places them (declared blocks by `order`, then
---strays in arrival order) — so `mod+h/l` always agrees with what is on
---screen.
---@param scene Scene.Spec
---@param tiles Scene.Tile[] tiled windows present on the scene's workspace
---@return Nav.Tile[]
function M.tile_order(scene, tiles)
  local representatives, members = layout.collapse_groups(tiles)
  local sequenced = layout.sequence(scene, representatives)
  local out = {}
  for _, entry in ipairs(sequenced) do
    local addresses = {}
    if entry.tile.group and members[entry.tile.group] then
      for _, member in ipairs(members[entry.tile.group]) do
        addresses[#addresses + 1] = member.address
      end
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

return M
