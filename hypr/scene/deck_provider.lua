-- The `deck` scene, registered as a Hyprland layout.
--
-- Thin shell over hypr/scene/deck.lua, mirroring hypr/scene/provider.lua's
-- shape: read the live windows a deck's columns subscribe to, ask the pure
-- function where they go, place the visible ones and dispatch the rest to
-- hold. Nothing here decides geometry or membership — that is deck.lua's
-- job; this module only executes what it reports (docs/deck.md "Why hidden
-- windows are HELD").
local spec_lib = require("hypr.scene.spec")
local deck = require("hypr.scene.deck")
local deck_order = require("hypr.scene.deck_order")
local scene_provider = require("hypr.scene.provider")
local dock_publish = require("hypr.scene.dock_publish")
local area_publish = require("hypr.scene.area_publish")

local M = {}

local NAME = "deck"

-- Where a deck's non-visible members park. One shared special workspace
-- (docs/deck.md leaves per-scene holding as an open question; a single area
-- is the simpler default and, like hypr/hyprfocus/hold.lua's HELD, is never
-- declared so no mode can ever admit or withdraw it).
local HOLD = "special:deck-hold"

-- Where the MODE parks a withdrawn scene's windows (hypr/hyprfocus/hold.lua).
-- Named rather than required: the deck must not depend on the mode engine, it
-- only has to recognise its holding place and keep its hands off.
local HYPRFOCUS_HELD = "special:hyprfocus-held"

---A gap value as one scalar: `gaps_in` has no directional meaning, and a
---sided `Scene.CssGap` table (the way Hyprland marshals gaps) collapses to
---its `left` so the deck's inter-column spacing stays a single number.
---@param value number|Scene.CssGap?
---@param fallback number
---@return number
local function scalar(value, fallback)
  if type(value) == "table" then
    return value.left or fallback
  end
  return tonumber(value) or fallback
end

---Gap precedence for a deck scene, the same ladder hypr/scene/provider.lua's
---private `gaps` reads (duplicated rather than exported, since neither module
---should reach into the other's internals for two lines of arithmetic): the
---scene's own declared `gaps_in`/`gaps_out` (LEO-397) win, then the host
---workspace-spec gaps (`conf/host.lua` resolves those from the monitor
---profile at load), then the compositor's global config, read live. `gaps_in`
---collapses to a scalar (it is only the space between columns); `gaps_out`
---is kept as a `Scene.CssGap` so top/bottom/sides are honoured separately.
---@param scene Scene.Spec
---@return number gaps_in, Scene.CssGap gaps_out
local function gaps(scene)
  local function raw(key, fallback)
    local ok, value = pcall(hl.get_config, key)
    if not ok or value == nil then
      return fallback
    end
    return value
  end
  local spec_in, spec_out
  local specs = config and config.host and config.host.workspaces and config.host.workspaces.workspace_specs
  for _, spec in ipairs(specs or {}) do
    if spec.default_name == scene.name then
      spec_in, spec_out = spec.gaps_in, spec.gaps_out
    end
  end
  local global_in = scalar(raw("general:gaps_in", 0), 0)
  local global_out = raw("general:gaps_out", 0)
  local gaps_in = scalar(scene.gaps_in, scalar(spec_in, global_in))
  -- `gaps_out` is directional: a bare number is uniform, a table names each
  -- side. `deck.lua` now consumes it with `layout.sides`, same as the scene
  -- layout, so an asymmetric outer gap (tighter top for the bar, say) no
  -- longer collapses to the left value on every side.
  local gaps_out = scene.gaps_out or spec_out or global_out
  return gaps_in, gaps_out
end

---Every window anywhere subscribing to `spec`'s columns — not only the ones
---currently tiled on the deck's own workspace, since a held member has
---already left it (docs/deck.md). Membership is class/tag matching, which
---has no notion of "current workspace".
---@param spec Scene.Spec
---@return Scene.Tile[]
---@return Scene.Tile[] tiles
---@return table<string, string> workspace_of live workspace name per address
local function member_tiles(spec)
  local tiles, workspace_of = {}, {}
  for _, w in ipairs(hl.get_windows() or {}) do
    local tile = scene_provider.window_tile(w)
    local at = w.workspace and w.workspace.name
    -- A member the MODE has parked is not this deck's to place. The engine
    -- withdrew the whole scene and moved its windows to the mode's holding
    -- place; a deck that still counted them asked the compositor to bring
    -- them home, which put a withdrawn scene's windows back on the desk --
    -- and the ones it wanted hidden went to the deck's own hold, a special
    -- workspace the compositor then shows over whatever IS active. That is
    -- the coding windows surfacing in a gaming mode. They come back when the
    -- mode admits the scene again, through `hold.restore` and nothing else.
    if at ~= HYPRFOCUS_HELD and deck.column_for(spec, tile) then
      tiles[#tiles + 1] = tile
      local ws = w.workspace
      if tile.address and ws and ws.name then
        workspace_of[tile.address] = ws.name
      end
    end
  end
  return tiles, workspace_of
end

---Put the hold workspace away if moving a member there pulled it into view.
---
---Moving a window to a special workspace makes the compositor show that
---special on the monitor, so a held member -- a window the deck means to be
---invisible -- ends up drawn over whatever workspace is active, including one
---belonging to another scene entirely.
local function hide_hold_if_shown()
  require("hypr.lib.nav").hide_special_if_shown(HOLD)
end

---Drop a closed window's address from every recorded deck column.
---
---The persisted record (hypr/scene/deck_order.lua) is what makes "new" mean
---"this column has never shown this window"; an address the compositor later
---hands to a different window would otherwise read as already-recorded and
---its column would not scroll to it. Called from the `window.close` hook,
---which is the only event that can retire an address.
---@param address string?
function M.forget(address)
  deck_order.forget(address)
end

---The live monitor a deck scene's workspace stands on, for the dock publish.
---@param scene_name string
---@return table?
local function monitor_of(scene_name)
  for _, monitor in ipairs(hl.get_monitors() or hl.monitors or {}) do
    local ws = monitor.activeWorkspace or monitor.active_workspace
    if ws and (ws.name or ws) == scene_name then
      return monitor
    end
  end
  -- Same reason as the scene provider's: a mismatched monitor would publish
  -- this scene's boxes under another output's name.
  return nil
end

---Publish where this scene's quickshell isles sit, off the boxes just placed.
---@param scene Scene.Spec
---@param scene_name string
---@param tiles Scene.Tile[]
---@param boxes Scene.Box[]
---@param gaps_in number
---Park a deck member and, when it held the keyboard, hand the keyboard
-- Moves this provider decides inside `recalculate`, dispatched a tick later
-- instead of from within the pass.
--
-- A window move re-enters the layout, and a re-entrant move lands in
-- `Layout::CWindowTarget::assignToSpace` while the current assignment is
-- still in flight -- which is an assert, a SIGSEGV, and the whole session
-- gone. It reached the desk as "a project does not open as a group": the
-- executor's group call recalculates the deck, the deck moved a window from
-- inside that recalculate, and the compositor died mid-grouping (crash
-- report: `CGroup::remove` -> `assignToSpace`). The decision still belongs
-- to the pass; only the dispatch waits for it to end.
local pending_moves = {}
local flush_scheduled = false

---Queue one move out of the layout pass. The last decision for an address
---in one pass is the one that stands -- a window asked home and then parked
---(or the reverse) within a single recalculate must not be dispatched twice.
---@param address string
---@param workspace string a `name:`/special workspace selector
local function queue_move(address, workspace)
  pending_moves[address] = workspace
  if flush_scheduled then
    return
  end
  flush_scheduled = true
  require("hypr.lib.hypr").oneshot(1, function()
    flush_scheduled = false
    local moves = pending_moves
    pending_moves = {}
    for target_address, target_workspace in pairs(moves) do
      hl.dispatch(hl.dsp.window.move({
        window = "address:" .. target_address,
        workspace = target_workspace,
        follow = false,
      }))
    end
  end)
end

---back to the member the strip now shows. Parking the member that holds
---focus drags focus into the hold with it (the compositor keeps the focused
---window focused through the move); when that special is hidden a beat
---later, Hyprland's own fallback drops the keyboard onto whatever window
---was focused before the scroll — the other column, which read as
---"scrolling swaps the focus". `shown_address` is the visible member this
---pass is laying out; the one-shot lets the park land first.
---@param address string
---@param workspace_of table<string, string>
---@param shown_address string?
local function park_member(address, workspace_of, shown_address)
  local at = workspace_of[address]
  if not at or at == HOLD then
    return
  end
  local active = hl.get_active_window()
  queue_move(address, HOLD)
  if active and active.address == address and shown_address then
    require("hypr.lib.hypr").oneshot(1, function()
      hl.dispatch(hl.dsp.focus({ window = "address:" .. shown_address }))
    end)
  end
end

---@param gaps_out number|Scene.CssGap
local function publish_docks(scene, scene_name, tiles, boxes, gaps_in, gaps_out)
  if not scene.docks then
    return
  end
  local monitor = monitor_of(scene_name)
  if not monitor then
    return
  end
  local top, right, bottom, left = require("hypr.scene.layout").sides(gaps_out)
  dock_publish.publish({
    scene = scene,
    monitor = monitor,
    tiles = tiles,
    boxes = dock_publish.settled(boxes, require("hypr.scene.provider").live_rects()),
    gaps_in = gaps_in or 0,
    gaps_out = { top = top, right = right, bottom = bottom, left = left },
    spec_lib = spec_lib,
  })
end

---Publish `docs/scenes.md`'s "Areas" for a deck scene: `work` is the area
---less the scene's outer gap, `columns` are the deck's own column boxes
---(`deck.column_boxes`, keyed by declared `order`) -- unlike a plain scene's
---blocks, a deck column is a PLACE that exists whether or not it currently
---shows a member, so this needs no tile geometry at all.
---@param scene Deck.Spec
---@param scene_name string
---@param area Scene.Area the area the compositor offered this pass
---@param gaps_in number?
---@param gaps_out (number|Scene.CssGap)?
local function publish_areas(scene, scene_name, area, gaps_in, gaps_out)
  local monitor = monitor_of(scene_name)
  if not monitor then
    return
  end
  local layout = require("hypr.scene.layout")
  local work_abs = layout.inner_area(area, gaps_out)
  local origin_x, origin_y = monitor.x or 0, monitor.y or 0
  local work = { x = work_abs.x - origin_x, y = work_abs.y - origin_y, w = work_abs.w, h = work_abs.h }

  local columns_by_order = {}
  for order, box in pairs(deck.column_boxes(scene, area, { gaps_in = gaps_in, gaps_out = gaps_out })) do
    columns_by_order[order] = { x = box.x - origin_x, y = box.y - origin_y, w = box.w, h = box.h }
  end

  area_publish.publish({
    scene_name = scene_name,
    monitor_name = monitor.name,
    work = work,
    columns_by_order = columns_by_order,
  })
end

---Point a column at a window that has just arrived in it.
---
---Without this, a newly-spawned window landed wherever its column's scroll
---already sat, was therefore not that column's visible member, and got parked
---in `HOLD` -- a special workspace, which the compositor then focuses. Opening
---a terminal on a deck workspace threw the desk onto an empty special
---workspace, which is the bug this exists to stop. Opening a window is an
---implicit request to see it, so its column scrolls to it rather than hiding
---it. A window scrolled away by hand is untouched: it is not new.
---
---The persisted record (hypr/scene/deck_order.lua) plays the "seen" set, in
---the order the column walks: an address is new when the column HAS a record
---and this pass's stack (recorded order plus arrivals) does not list it. A
---column with no record yet is all "never seen" but scrolls nothing — a
---brand-new deck must not yank its first pass to a scrolled position, the
---same reason the old session-only set skipped its first pass. Every pass
---folds the merged order — recorded addresses in record order, arrivals
---appended — back into the record, which prunes addresses of windows that
---left without closing and makes "new" apply exactly once per window. The
---prune skips members the MODE has parked on the holding place: they are not
---gone, and pruning them made their homecoming read as a first arrival — the
---column scrolled to the returning window and re-parked the one that had
---been visible, leaving the record pointing at a hidden member.
---@param spec Deck.Spec
---@param scene_name string
---@param tiles Scene.Tile[]
---@param records table<integer, { order: string[], scroll: number? }> this
---scene's persisted records, read by the caller
---@param held table<string, boolean>? addresses the mode holds right now
---@return table<integer, { order: string[], scroll: number? }> the records,
---folded and persisted (dirty-guarded: an unchanged column is not written)
local function scroll_to_arrivals(spec, scene_name, tiles, records, held)
  held = held or {}
  local order = {}
  for column_order, record in pairs(records) do
    order[column_order] = record.order
  end
  for column_order, stack in pairs(deck.stacks(spec, tiles, order)) do
    local record = records[column_order]
    local scroll
    if record then
      local listed = {}
      for _, address in ipairs(record.order) do
        listed[address] = true
      end
      for index, tile in ipairs(stack) do
        -- An arrival is a member this pass records for the first time: the
        -- record exists (this is not a brand-new column) and the address
        -- sits beyond the recorded order — the merged stack carries it
        -- because the window genuinely just opened. A member home from the
        -- mode's holding place is still recorded (the merge below keeps it)
        -- and therefore never reads as new.
        if tile.address and not listed[tile.address] and not held[tile.address] then
          scroll = index
          break
        end
      end
    end
    local in_stack = {}
    for _, tile in ipairs(stack) do
      if tile.address then
        in_stack[tile.address] = true
      end
    end
    local merged = {}
    local seen = {}
    for _, address in ipairs(record and record.order or {}) do
      -- Recorded members stay recorded while they exist somewhere: on the
      -- deck, or parked by the mode. An address the compositor no longer
      -- knows and the mode does not hold is a window that vanished without
      -- a close event, and its slot is dropped (`M.forget` retires the ones
      -- that closed properly).
      if not seen[address] and (in_stack[address] or held[address]) then
        seen[address] = true
        merged[#merged + 1] = address
      end
    end
    for _, tile in ipairs(stack) do
      if tile.address and not seen[tile.address] then
        seen[tile.address] = true
        merged[#merged + 1] = tile.address
      end
    end
    records[column_order] = deck_order.record(scene_name, column_order, merged, scroll or (record and record.scroll))
  end
  return records
end

---Deck-opted scenes only, keyed by workspace name — `deck.applies` is the
---one opt-in check (docs/deck.md), so a scene left on `layout = "scene"`
---never reaches this provider at all.
---@param scenes table<string, Scene.Spec>
---@return table<string, Scene.Spec>
local function deck_scenes(scenes)
  local out = {}
  for name, scene in pairs(scenes) do
    if deck.applies(scene) then
      out[name] = scene
    end
  end
  return out
end

---@param scenes table<string, Scene.Spec>|fun(): table<string, Scene.Spec>
function M.register(scenes)
  -- Same contract as `hypr/scene/provider.lua`'s register, and for the same
  -- reason (LEO-397): `M.attach()` passes a resolver so every recalculate
  -- re-reads the live declaration. Resolving once at registration froze the
  -- deck set to whatever the store held at config-load -- before it was
  -- readable, that set came up empty, `scene_name` below never matched, and
  -- the deck silently drew nothing on a workspace that declares it. Tests
  -- pass a plain table fixture, read once, which is fine since they own the
  -- whole lifetime of that table.
  local get_scenes = type(scenes) == "function" and scenes or function()
    return scenes
  end
  hl.layout.register(NAME, {
    recalculate = function(ctx)
      local decks = deck_scenes(get_scenes())
      local targets = ctx.targets or {}
      local scene_name
      for _, target in ipairs(targets) do
        local ws = target.window and target.window.workspace
        if ws and ws.name and decks[ws.name] then
          scene_name = ws.name
          break
        end
      end
      if not scene_name then
        return
      end
      -- Same containment as the scene provider's: an error handed back to the
      -- compositor in place of a placement drops that pass's windows out of
      -- the tiling entirely.
      local ok, err = pcall(M.place, decks[scene_name], scene_name, ctx)
      if not ok then
        require("hypr.lib.trace").emit({
          stage = "arrange",
          event = "layout_failed",
          decision = "skip",
          reason = ("deck layout raised: %s"):format(tostring(err)),
          scene = scene_name,
        })
      end
    end,
  })
end

---Split the persisted records into the two maps `deck.boxes` takes: the
---recorded address list per column (strip order, which survives a reload)
---and the recorded visible index per column.
---@param records table<integer, { order: string[], scroll: number? }>
---@return table<integer, string[]> order
---@return table<integer, number?> scroll
local function order_and_scroll(records)
  local order, scroll = {}, {}
  for column_order, record in pairs(records) do
    order[column_order] = record.order
    scroll[column_order] = record.scroll
  end
  return order, scroll
end

---Place one deck scene's windows into `ctx`.
---
---Exposed rather than kept inside the registered layout because a deck
---workspace cannot actually select this layout on this build: a workspace
---rule's `layout` resolves BUILTIN layouts only (verified live -- `master`
---and `dwindle` take, while `scene`, `deck`, `lua:scene` and `lua:deck` all
---fall through), and only `general:layout` accepts a custom Lua one. So the
---deck runs inside the `scene` layout, which is the one every workspace
---already has, and `hypr/scene/provider.lua` delegates here for a scene
---declaring `layout = "deck"`. The registration above stays for a host that
---can select it directly.
---@param scene Scene.Spec
---@param scene_name string
---@param ctx HL.LayoutContext
function M.place(scene, scene_name, ctx)
  do
    local targets = ctx.targets or {}
    local by_address = {}
    for _, target in ipairs(targets) do
      if target.window and target.window.address then
        by_address[target.window.address] = target
      end
    end

    local gaps_in, gaps_out = gaps(scene)
    local tiles, workspace_of = member_tiles(scene)
    -- Members the mode holds right now: the record keeps their slots, so
    -- their homecoming is a return to the recorded position, not an arrival
    -- the column scrolls to.
    local held = {}
    for _, w in ipairs(hl.get_windows() or {}) do
      local at = w.workspace and w.workspace.name
      if at == HYPRFOCUS_HELD and w.address then
        held[w.address] = true
      end
    end
    local records = deck_order.get_all(scene_name)
    records = scroll_to_arrivals(scene, scene_name, tiles, records, held)
    local order, scroll = order_and_scroll(records)
    local boxes, hold = deck.boxes(scene, tiles, ctx.area, {
      gaps_in = gaps_in,
      gaps_out = gaps_out,
      order = order,
      scroll = scroll,
    })
    for _, box in ipairs(boxes) do
      local target = by_address[box.address]
      if target then
        target:place({ x = box.x, y = box.y, w = box.w, h = box.h })
      else
        -- Not tiled here yet (freshly scrolled to, or freshly held
        -- elsewhere): ask it home, from outside this pass (`queue_move`).
        -- The move triggers another `recalculate`, which is the pass that
        -- actually places it — this one only reports the need, same as
        -- `deck.lua`'s own contract.
        queue_move(box.address, "name:" .. scene_name)
      end
    end

    -- Which member each COLUMN is showing, so parking the window that holds
    -- focus hands it to that column's own visible member. `boxes[1]` is the
    -- first box of the first column, so a parked member of the second column
    -- used to throw focus sideways into the first -- the neighbour-stray
    -- this reads as on the desk, and a monitor hop when the columns span two
    -- (`docs/declared-groups.md` rule 3).
    local tile_by_address = {}
    for _, tile in ipairs(tiles) do
      if tile.address then
        tile_by_address[tile.address] = tile
      end
    end
    local shown_by_column = {}
    local function column_order_of(address)
      local tile = tile_by_address[address]
      local column = tile and deck.column_for(scene, tile)
      return column and column.order
    end
    for _, box in ipairs(boxes) do
      local order_key = column_order_of(box.address)
      if order_key and not shown_by_column[order_key] then
        shown_by_column[order_key] = box.address
      end
    end
    for _, address in ipairs(hold) do
      park_member(address, workspace_of, shown_by_column[column_order_of(address)])
    end

    hide_hold_if_shown()

    -- Read-only tail, the same one the scene provider runs: a scene's isles
    -- hang off the boxes just placed. It writes to the `geometry` store and
    -- nowhere else -- no place, no dispatch, no recalculate.
    publish_docks(scene, scene_name, tiles, boxes, gaps_in, gaps_out)
    publish_areas(scene, scene_name, ctx.area, gaps_in, gaps_out)
  end
end

---Show the thing `address` belongs to, and put focus on `address`.
---
---The one act `docs/declared-groups.md` rule 4 names: a front-end that has
---just opened (or been asked for) a declared group calls this and nothing
---else. It scrolls that thing's column to it, brings the whole thing home
---and focuses the window asked for -- once, deliberately, which is the only
---focus move the contract allows. Everything else on the desk is left
---alone: no other column is scrolled, no neighbour re-homed.
---
---Called over `hyprctl eval` by `bin/,proj.sh`, so a helper never has to
---know what a column, a scroll index or a hold workspace is.
---@param address string a window address, with or without the `address:` prefix
---@return boolean whether a deck showed it
function M.present(address)
  address = address:gsub("^address:", "")
  local w = hl.get_window("address:" .. address)
  if not w then
    return false
  end
  -- The scene by tag, not by workspace: the window may be parked on the hold
  -- right now, and the hold owns no scene (same reason the grouping executor
  -- reads the tag).
  local scenes = spec_lib.load() or {}
  local scene_name = w.workspace and w.workspace.name
  if not (scene_name and scenes[scene_name]) then
    scene_name = nil
    for _, tag in ipairs(w.tags or {}) do
      local named = tag:match("^scene:([^*]+)")
      if named and scenes[named] then
        scene_name = named
        break
      end
    end
  end
  local scene = scene_name and scenes[scene_name]
  if not (scene and deck.applies(scene)) then
    return false
  end

  local tiles = member_tiles(scene)
  local column = deck.column_for(scene, scene_provider.window_tile(w))
  if not column then
    return false
  end
  local order = order_and_scroll(deck_order.get_all(scene_name))
  local stack = deck.stacks(scene, tiles, order)[column.order] or {}
  local representatives = require("hypr.scene.layout").collapse_groups(stack, function(tile)
    return deck.thing_key(scene, tile)
  end)
  local wanted = deck.thing_key(scene, scene_provider.window_tile(w))
  local index
  for i, rep in ipairs(representatives) do
    if rep.address == address or (wanted and deck.thing_key(scene, rep) == wanted) then
      index = i
      break
    end
  end
  if not index then
    return false
  end

  deck_order.set_scroll(scene_name, column.order, index)
  M.reconcile(scene_name)
  -- After the bring-home moves, not with them: the move lands on its own
  -- pass, and focusing before it has would focus a window still parked.
  require("hypr.lib.hypr").oneshot(1, function()
    hl.dispatch(hl.dsp.focus({ window = "address:" .. address }))
  end)
  return true
end

---Bring a deck scene's windows to where its scroll says they belong, from
---OUTSIDE a layout callback.
---
---`M.place` already computes this, but it runs inside `recalculate`, and a
---window move dispatched from there only lands when a real compositor event
---drove the pass -- a `layoutmsg`-driven recalculate silently drops them
---(verified live: closing a window left its column empty for as long as you
---like, while switching workspace and back fixed it instantly). So an event
---handler calls this instead: it dispatches only the moves, and the
---compositor's own recalculate that each move triggers does the placing.
---@param scene_name string workspace/scene name
function M.reconcile(scene_name)
  local scenes = spec_lib.load()
  local scene = scenes and scenes[scene_name]
  if not scene or not deck.applies(scene) then
    return
  end
  local area
  for _, m in ipairs(hl.get_monitors() or {}) do
    local ws = m.active_workspace
    if ws and (ws.name or ws) == scene_name then
      area = { x = m.x, y = m.y, w = m.width, h = m.height }
      break
    end
  end
  if not area then
    return
  end
  local tiles, workspace_of = member_tiles(scene)
  local gaps_in, gaps_out = gaps(scene)
  local order, scroll = order_and_scroll(deck_order.get_all(scene_name))
  local boxes, hold = deck.boxes(scene, tiles, area, {
    gaps_in = gaps_in,
    gaps_out = gaps_out,
    order = order,
    scroll = scroll,
  })
  -- Whether anything the deck wants shown is currently focused. Read BEFORE
  -- the moves below, because a window arriving does not change focus
  -- (`follow = false`) and so cannot answer this afterwards.
  local active = hl.get_active_window()
  local first_home
  for _, box in ipairs(boxes) do
    if workspace_of[box.address] ~= scene_name then
      first_home = first_home or box.address
      hl.dispatch(hl.dsp.window.move({
        window = "address:" .. box.address,
        workspace = "name:" .. scene_name,
        follow = false,
      }))
    end
  end
  -- Closing the focused window leaves focus on NOTHING, and the member the
  -- deck brings home to replace it arrives unfocused (`follow = false`, so
  -- an ordinary swap does not yank focus). The result was a visible window
  -- the keyboard could not reach at all: not focusable, not closable. So
  -- when the deck brings something home and the keyboard has nowhere to be,
  -- focus what arrived.
  --
  -- "Nowhere to be" means exactly that: no active window. It used to mean
  -- "the active window is not one of the boxes I placed", which quietly
  -- stole focus from anything the deck does not place -- a floating stray,
  -- and the project picker is one. Opening the picker on a deck scene
  -- therefore gave you a prompt you could not type into (live complaint,
  -- 2026-09-24). A window that holds focus keeps it, placed or not
  -- (`docs/declared-groups.md` rule 3).
  if first_home and not (active and active.address) then
    require("hypr.lib.hypr").oneshot(1, function()
      hl.dispatch(hl.dsp.focus({ window = "address:" .. first_home }))
    end)
  end
  for _, address in ipairs(hold) do
    park_member(address, workspace_of, boxes[1] and boxes[1].address)
  end
  hide_hold_if_shown()
end

---Register with whatever the host declares. Separate from `register` so
---tests can drive the provider with their own scenes.
function M.attach()
  M.register(spec_lib.load)
end

-- Exported so the mode engine can find these windows: a deck member parked
-- here still belongs to its scene, and a mode that withdraws that scene has to
-- take them with it (hypr/hyprfocus/hold.lua).
M.HOLD = HOLD

return M
