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

---The name of the workspace active on `monitor`, or nil.
---
---The live binding spells this field `active_workspace` (snake_case, an
---`HL.Workspace` userdata) — `activeWorkspace` is `hyprctl`'s JSON spelling
---and is `nil` on every monitor the Lua API hands out. Reading the camelCase
---one compiled, tested (fixtures carried the JSON spelling) and silently
---answered "unknown" forever: a drawer could not tell an already-focused
---owner workspace from a cold one, cross-monitor tile navigation never saw
---the adjacent monitor's scene, and a held window with no origin was never
---rescued because the rescue target came back nil. Both spellings are read
---here so a fixture written either way still means what it says.
---@param monitor table?
---@return string?
function M.monitor_workspace(monitor)
  local ws = monitor and (monitor.active_workspace or monitor.activeWorkspace)
  return ws and ws.name or nil
end

---The name of the workspace active on the monitor called `name`, or nil.
---@param monitors table[]?
---@param name string?
---@return string?
function M.workspace_on(monitors, name)
  if not name then
    return nil
  end
  for _, m in ipairs(monitors or {}) do
    if m.name == name then
      return M.monitor_workspace(m)
    end
  end
  return nil
end

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

---The tile `w` stands in, resolving a group member to its group's tile.
---
---A deck tile names one address per thing (`layout.collapse_groups` keeps
---each group's FIRST member as its representative), so looking a focused
---window up by its own address finds nothing whenever focus sits on any
---other member of a group — which is every member but one. `mod+ctrl+j/k`
---read that as "not on the deck" and did nothing at all on a grouped tile.
---Match the whole group, not just the address that happens to represent it.
---@param tiles Nav.Tile[]
---@param w HL.Window
---@return integer?
function M.tile_index_for_window(tiles, w)
  if not w or not w.address then
    return nil
  end
  local index = M.tile_index(tiles, w.address)
  if index then
    return index
  end
  local members = w.group and w.group.members
  members = (members and members.title) and { members } or (members or {})
  for _, member in ipairs(members) do
    if member.address then
      index = M.tile_index(tiles, member.address)
      if index then
        return index
      end
    end
  end
  return nil
end

---Which entry of a strip a window stands in: the entry naming the same THING
---as the focused window.
---
---A `flip` column's strip lists one representative per thing, so stepping it
---by the focused address alone matched nothing whenever focus sat on any
---other member (every tab but one). The caller then read "no neighbour" as
---"wrap to the first", and the press travelled to the index instead of
---scrolling one step (live complaint, 2026-09-24).
---
---`entries` carries the key with the address because deciding what a window
---belongs to needs the compositor, and this module never touches it.
---@param entries { address: string, key: string? }[] the strip, in order
---@param address string the focused window's address
---@param key string? the thing the focused window belongs to
---@return string? the representative of that thing, or nil
function M.thing_address(entries, address, key)
  for _, entry in ipairs(entries or {}) do
    if entry.address == address then
      return entry.address
    end
  end
  if not key then
    return nil
  end
  for _, entry in ipairs(entries or {}) do
    if entry.key and entry.key == key then
      return entry.address
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

-- === Deck columns (docs/deck.md) ===

---A deck's columns as `Nav.Tile`s, one per non-empty column, so `mod+h/l`
---can walk them with the exact same `M.decide` a scene's blocks use — a
---deck column is a tile like any other. `addresses` leads with the column's
---currently shown member (`scroll`, clamped by `hypr/scene/deck.lua`'s
---`clamp_scroll`) so crossing into a column lands on what it already shows,
---the same "enter lands on current" rule a group tile gives (LEO-380).
---`plain` keeps the column's arrival order untouched, for `mod+j/k` below to
---step through with `M.window_neighbor` — reordering `addresses` to lead
---with the shown member would break that stepping.
---@param spec Scene.Spec deck spec (`columns` normalized by hypr/scene/spec.lua)
---@param tiles Scene.Tile[] every window subscribed to spec's columns, any workspace
---@param records table<integer, { order: string[], scroll: number? }> the
---persisted records per column (hypr/scene/deck_order.lua): the strip is
---walked in the recorded order so navigation follows the arrangement the
---user built it into, and the recorded scroll is the entered column's
---already-shown member
---@param enter fun(members: Scene.Tile[]): string?  which member of a
---collapsed THING the strip should stand on. A deck column's entry is one
---thing (`deck.thing_key`), and a project is a whole group of terminals
---collapsed into one -- so the address that names it was simply the group's
---FIRST member, and crossing into the column from outside yanked that one
---forward instead of the terminal you were last in (live, 2026-09-25). The
---caller resolves it through the group's own adapter, which already records
---the last-focused member; a thing with nothing recorded (or a lone window)
---keeps the representative.
---@return (Nav.Tile|{ plain: string[], column: integer })[]
function M.deck_tile_order(spec, tiles, records, enter)
  local deck = require("hypr.scene.deck")
  local columns = {}
  for _, c in ipairs(spec.columns or {}) do
    columns[#columns + 1] = c
  end
  table.sort(columns, function(a, b)
    return a.order < b.order
  end)
  local order = {}
  for column_order, record in pairs(records) do
    order[column_order] = record.order
  end
  local stacks = deck.stacks(spec, tiles, order)
  local out = {}
  for _, column in ipairs(columns) do
    -- Declared identity, the same one the deck lays out by
    -- (`docs/declared-groups.md`): navigation must walk the same strip the
    -- eye sees, and a project mid-spawn is one thing on it, not four.
    local representatives, members = layout.collapse_groups(stacks[column.order] or {}, function(tile)
      return deck.thing_key(spec, tile)
    end)
    local plain = {}
    for _, rep in ipairs(representatives) do
      local key = deck.thing_key(spec, rep)
      local chosen = enter and key and enter(members[key] or { rep }) or nil
      plain[#plain + 1] = chosen or rep.address
    end
    if #plain > 0 then
      local record = records[column.order]
      local index = deck.clamp_scroll(record and record.scroll or nil, #plain)
      local shown = plain[index]
      local addresses = { shown }
      for _, address in ipairs(plain) do
        if address ~= shown then
          addresses[#addresses + 1] = address
        end
      end
      out[#out + 1] =
        { key = "deck:" .. column.order, addresses = addresses, group = false, plain = plain, column = column.order }
    end
  end
  return out
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
---window: HL.Window?,
---dir: "left"|"right",
---target: { tiles: Nav.Tile[] }?}
---@return Nav.Action
function M.decide(ctx)
  -- By the window when the caller has one: a deck tile names one address per
  -- thing, so resolving by address alone found no tile whenever focus sat on
  -- any group member but the representative, and `mod+h/l` died in both
  -- directions until focus happened to land on the shown member.
  local index = ctx.window and M.tile_index_for_window(ctx.tiles, ctx.window)
    or (ctx.active and M.tile_index(ctx.tiles, ctx.active))
    or nil
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

---The special workspace a monitor is currently showing, or nil. The Lua
---monitor object spells it `active_special_workspace`; older shapes used
---`specialWorkspace`, so both are read (the wrong one silently hid the special
---from every caller — shelf sizing, the ignored-monitor relocation).
---@param monitor table?
---@return string? the special's name, `special:` prefix included
function M.special_workspace(monitor)
  local special = monitor and (monitor.active_special_workspace or monitor.specialWorkspace)
  return special and special.name or nil
end

---Hide a special workspace if any monitor is currently showing it.
---Moving a window to a special can make the compositor show that special on
---the monitor; for hidden holding places that is a visible bug. The toggle is
---deferred by a tick so a caller inside a layout pass or move handler does not
---re-enter its own callback.
---@param special string full workspace name with `special:` prefix
function M.hide_special_if_shown(special)
  local prefix = string.match(special, "^special:(.*)$") or special
  for _, monitor in ipairs(hl.get_monitors() or {}) do
    if M.special_workspace(monitor) == special then
      require("hypr.lib.hypr").oneshot(1, function()
        hl.dispatch(hl.dsp.workspace.toggle_special(prefix))
      end)
      return
    end
  end
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

---The monitor focus should return to after a special was relocated off an
---ignored monitor: the monitor the user was already on, when it is usable and
---not the primary the relocation flashed through. Nil when there is nothing to
---restore (the user was on the ignored monitor itself, or on the primary), so
---the relocation is never followed by a pointless focus dispatch.
---@param ignored string[]?
---@param before string? the focused monitor when the relocation started
---@param primary string?
---@return string?
function M.restore_after_relocate(ignored, before, primary)
  if not before or before == primary then
    return nil
  end
  if M.is_ignored(ignored, before) then
    return nil
  end
  return before
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
  local primary_workspace = M.workspace_on(monitors, primary)
  for _, m in ipairs(monitors or {}) do
    local special = M.special_workspace(m)
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

-- === Undeclared workspaces (LEO-382) ===

---Whether `name` is a plain workspace `workspace_specs` declares
---(`default_name`), the only names a scene, shelf or binding can ever
---address. Hyprland gives every monitor a numbered workspace of its own at
---startup; a window that opens or lands there before anything claims it sits
---on a name nothing reaches.
---@param workspace_specs HL.WorkspaceRuleSpec[]?
---@param name string?
---@return boolean
function M.is_declared_workspace(workspace_specs, name)
  for _, spec in ipairs(workspace_specs or {}) do
    if spec.default_name == name then
      return true
    end
  end
  return false
end

---The declared plain workspace `workspace_specs` puts on `monitor`, or nil
---when the host names none there. Several specs can share a monitor
---(`docs/scenes.md`'s secondary carries `obsidian-linear`, `media` and
---`logs`); the one marked `default = true` wins, falling back to the first
---declared for that monitor in file order when none is marked — a stable,
---inspectable pick over guessing from whatever happens to be active (the
---window this decides for may itself be squatting on the monitor's live
---active workspace).
---@param workspace_specs HL.WorkspaceRuleSpec[]?
---@param monitor string?
---@return string?
function M.declared_workspace_for_monitor(workspace_specs, monitor)
  if not monitor then
    return nil
  end
  local fallback
  for _, spec in ipairs(workspace_specs or {}) do
    if spec.monitor == monitor and spec.default_name and not tostring(spec.workspace):find(":", 1, true) then
      if spec.default then
        return spec.default_name
      end
      fallback = fallback or spec.default_name
    end
  end
  return fallback
end

---What keeps a window off an undeclared workspace (LEO-382): the same
---treatment `off_ignored` gives an ignored monitor, extended to any plain
---workspace `workspace_specs` does not name. A special is never a target
---here (it is either a drawer/shelf or the engine-owned hold area, both
---reachable by construction) and neither is an ignored monitor's own plain
---workspace — `off_ignored` already owns that redirect, and letting this
---function also act on it would dispatch two competing moves for one event.
---A monitor with no declared workspace of its own (or one this host ignores)
---falls back to the primary's declared workspace, the same "somewhere
---reachable" fallback `off_ignored` and the reachability invariant's
---`no_origin` both use.
---
---Deliberately narrow to open/move events, never a sweep: a window standing
---on an undeclared workspace has never been placed there by any scene, mode
---or binding (nothing addresses it), so unlike `collect` — which must leave
---a member the user parked elsewhere alone — there is no user intent this
---could fight. A user cannot even reach an undeclared workspace through the
---bound UI; only a script or `hyprctl` driving one there directly could
---trigger this, and moving it home is exactly what should happen next.
---@param workspace_specs HL.WorkspaceRuleSpec[]?
---@param ignored string[]?
---@param primary string?
---@param w table? the window an event carried
---@return { move: string, workspace: string }[] actions
function M.off_undeclared(workspace_specs, ignored, primary, w)
  local actions = {}
  local ws = w and w.workspace
  local name = ws and ws.name
  if not name or tostring(name):find("^special:") then
    return actions
  end
  if M.is_declared_workspace(workspace_specs, name) then
    return actions
  end
  local monitor = ws.monitor and ws.monitor.name
  if M.is_ignored(ignored, monitor) then
    return actions
  end
  local target = M.declared_workspace_for_monitor(workspace_specs, monitor)
    or M.declared_workspace_for_monitor(workspace_specs, primary)
  if target and target ~= name then
    actions[#actions + 1] = { move = w.address, workspace = target }
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
