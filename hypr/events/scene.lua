-- Window scene engine (LEO-245): drive window positioning from the scene.
--
-- A scene is a per-workspace arrangement of *blocks*. Each block names the
-- window classes it owns and the invariants that hold between those windows:
--
--   * `group` — every matching window lives in one Hyprland group, so the
--     block is a single tile however many windows it has;
--   * `order` — where the block's tile sits in the left-to-right sequence;
--   * `share` — the fraction of the work area the block's tile should hold.
--
-- The scene specs live in the host config next to `workspace_specs`
-- (hyprland.lua), keyed by the workspace's `default_name`.
--
-- Why a driver at all: Hyprland's positioning primitives act on the *focused*
-- window — the `window:` argument is ignored — and `moveintogroup` additionally
-- requires the target group to be adjacent on that axis (verified live, with a
-- real Dofus/zen scene, on the running build). There is no window-targeted
-- dispatch (this is exactly the finding LEO-214 recorded). So corrective
-- actions are a *focus-dance*: focus the window, dispatch, restore focus
-- (LEO-129). The loop converges because `window.resize` is exact on tiled
-- windows and adjacency is reachable in a bounded number of `movewindow` hops.
--
-- The driver reacts only to scene-window map/close. It never polls and never
-- fights a scene that already satisfies its blocks; every correction is
-- verified and stops at tolerance.

local hyg = require("hypr.lib.hypr")

-- How long after a window maps until its tiled geometry (`at`/`size`,
-- GEOMETRIC_GOAL) is final and directions/sizes can be aimed.
local SETTLE_MS = 100
-- Re-check the scene shortly after a corrective dispatch.
local VERIFY_MS = 80
-- Bounded `movewindow` hops to reach adjacency before giving up on a join.
local MAX_HOPS = 4
-- Bounded corrections per realize before stopping (a single join can take
-- several hops' worth of turns).
local MAX_TURNS = 8
-- A block that holds `share` +/- 2% of the work area is done.
local SHARE_TOL = 0.02

-- Scene state keyed by workspace `default_name`. Built once at require from
-- `config.host.workspaces.scenes`; the per-block membership sets are mutated
-- as windows fold in, so the scene is "that set", not whatever Hyprland
-- happens to be splitting.
---@class Scene
---@field name string workspace `default_name` (the scene's own identity)
---@field blocks SceneBlock[]
---@field members table<integer, table<string, true>> membership per block order
---@field busy boolean a realize is in flight for this scene
---@field pending boolean a realize is armed but not yet started the loop
---@field last_fix string? the most recent correction applied in this pass
---@field last_digest string? geometry digest of the previous step
---@class SceneBlock
---@field classes string[]
---@field group boolean
---@field order integer
---@field share number|nil
local scenes = {}

local function build()
  for _, spec in ipairs(config.host.workspaces.scenes or {}) do
    local blocks = {}
    for i, block in ipairs(spec.blocks) do
      blocks[i] = {
        classes = block.classes,
        group = block.group == true,
        order = block.order,
        share = block.share,
      }
    end
    table.sort(blocks, function(a, b)
      return a.order < b.order
    end)
    local members = {}
    for _, block in ipairs(blocks) do
      members[block.order] = {}
    end
    scenes[spec.default_name] = {
      name = spec.default_name,
      blocks = blocks,
      members = members,
      busy = false,
      pending = false,
      last_digest = nil,
      last_fix = nil,
    }
  end
end

---@param scene Scene
---@param w HL.Window
---@return boolean
local function on_scene(scene, w)
  -- A scene is keyed by its workspace `default_name`, not by the integer id:
  -- ids are assigned by the compositor at creation and are host data (this
  -- host runs gaming on id 4 while the spec writes "5"), so a member check
  -- against spec numbers is a race-wired guess. `default_name` is the one
  -- identity that means the same thing on every host (LEO-235 contract).
  local ws = w and w.workspace
  return ws ~= nil and ws.name == scene.name
end

---A class entry may be a plain literal ("Dofus.x64", "zen-gaming-media",
---"Kitty-Main") or a pattern ("Proj-[A-Za-z0-9_-]+") — the same dual meaning
---windowrules.lua gives class rules. Literals first, so hyphenated classes
---never trip on `-` being a Lua-pattern quantifier.
---@param w HL.Window
---@param patterns string[]
---@return boolean
local function class_matches(w, patterns)
  local cls = w and w.class
  if not cls then
    return false
  end
  for _, entry in ipairs(patterns) do
    if cls == entry or cls:match("^(" .. entry .. ")$") then
      return true
    end
  end
  return false
end

---@param scene Scene
---@param w HL.Window
---@return SceneBlock?
local function block_for(scene, w)
  for _, block in ipairs(scene.blocks) do
    if class_matches(w, block.classes) then
      return block
    end
  end
  return nil
end

---@return table<string, HL.Window>
local function live_map()
  local live = {}
  for _, w in ipairs(hl.get_windows() or {}) do
    live[w.address] = w
  end
  return live
end

---HL.Group.members is a bare HL.Window when the group holds exactly one,
---otherwise an array — normalize to an array (same shape team.lua reads).
---@param group HL.Group?
---@return HL.Window[]
local function group_members(group)
  local members = group and group.members
  if not members then
    return {}
  end
  if members.title then
    return { members }
  end
  return members
end

---The live addresses of every window sharing `w`'s group.
---@param w HL.Window
---@param live table<string, HL.Window>
---@return table<string, true>
local function window_group_set(w, live)
  local out = {}
  for _, member in ipairs(group_members(w and w.group)) do
    if live[member.address] then
      out[member.address] = true
    end
  end
  return out
end

---@param a table<string, true>
---@param b table<string, true>
---@return boolean
local function sets_overlap(a, b)
  for address in pairs(a) do
    if b[address] then
      return true
    end
  end
  return false
end

---Fold `w`'s live group into the authoritative membership set (a group may
---carry dead members on close; those are dropped so the set never points at
---windows that are gone).
---@param w HL.Window
---@param members table<string, true>
---@param live table<string, HL.Window>
local function record_group(w, members, live)
  for _, member in ipairs(group_members(w and w.group)) do
    if live[member.address] then
      members[member.address] = true
    end
  end
end

---@param w HL.Window
---@return number, number window center
local function center(w)
  return w.at.x + w.size.x / 2, w.at.y + w.size.y / 2
end

---@param a HL.Window
---@param b HL.Window
---@return string "l"|"r"|"u"|"d" direction from a's center to b's center
local function direction_to(a, b)
  local ax, ay = center(a)
  local bx, by = center(b)
  local dx, dy = bx - ax, by - ay
  if math.abs(dx) >= math.abs(dy) then
    return dx >= 0 and "r" or "l"
  end
  return dy >= 0 and "d" or "u"
end

---@param a HL.Window
---@param b HL.Window
---@param dir string
---@return boolean whether b sits adjacent to a in `dir` (whether its edge
---touches a's, within a couple of pixels — "somewhere to the left" is not
---adjacent, mergeable is)
local function adjacent_in_direction(a, b, dir)
  local gap
  if dir == "r" then
    gap = b.at.x - (a.at.x + a.size.x)
  elseif dir == "l" then
    gap = a.at.x - (b.at.x + b.size.x)
  elseif dir == "d" then
    gap = b.at.y - (a.at.y + a.size.y)
  else
    gap = a.at.y - (b.at.y + b.size.y)
  end
  return gap >= -1 and gap <= 2
end

---@param target HL.Window
---@param live table<string, HL.Window>
---@param members table<string, true>
---@return HL.Window? the live group member nearest to `target`, if any
local function nearest_member(target, live, members)
  local nearest, nearest_sq = nil, nil
  for address in pairs(members) do
    local member = live[address]
    if member and member.at and member.size then
      local dx, dy = center(target)
      local mx, my = center(member)
      local dist = (mx - dx) * (mx - dx) + (my - dy) * (my - dy)
      if nearest_sq == nil or dist < nearest_sq then
        nearest, nearest_sq = member, dist
      end
    end
  end
  return nearest
end

---@param prev HL.Window?
---@param current_address string
local function restore_focus(prev, current_address)
  if prev and prev.address and prev.address ~= current_address then
    hl.dispatch(hl.dsp.focus({ window = "address:" .. prev.address }))
  end
end

---Fold `stray` into its block's authoritative group. The primitive takes a
---direction, not a target, and only reaches the window *beside* the group, so
---the stray hops toward the nearest member with `movewindow` until adjacent,
---then `moveintogroup` merges it. Focus is handed back when the fold settles
---or gives up (LEO-129). Completes via `cont(true)` when a merge was aimed,
---`cont(false)` when there was nothing to do (re-seed or dead end); the next
---realize turn re-checks membership either way.
---@param stray HL.Window
---@param members table<string, true>
---@param cont fun(aimed: boolean)
local function fold_stray(stray, members, cont)
  local prev = hl.get_active_window()
  local did_focus = false

  local function terminal()
    if did_focus then
      restore_focus(prev, stray.address)
    end
  end

  local function reseed()
    record_group(stray, members, live_map())
    terminal()
    cont(false)
  end

  local function attempt(hops)
    if hops > MAX_HOPS then
      terminal()
      cont(false)
      return
    end
    local live = live_map()
    local me = live[stray.address]
    if not me or not me.at or not me.size then
      terminal()
      cont(false)
      return
    end

    -- Already merged (the group tile absorbed it while we looked away).
    if sets_overlap(window_group_set(me, live), members) then
      record_group(me, members, live)
      terminal()
      cont(true)
      return
    end
    -- The authoritative set holds only dead addresses: this window is the new
    -- seed of the block's group.
    if not next(members) then
      reseed()
      return
    end

    local member = nearest_member(me, live, members)
    if not member then
      reseed()
      return
    end

    local dir = direction_to(me, member)
    if adjacent_in_direction(me, member, dir) then
      hl.dispatch(hl.dsp.focus({ window = "address:" .. me.address }))
      did_focus = true
      hl.dispatch(hl.dsp.window.move({ into_group = dir }))
      -- Fold the stray's address in immediately (its pre-merge group is
      -- itself); the verify step re-reads the merged group either way.
      record_group(me, members, live)
      terminal()
      cont(true)
      return
    end

    -- Hop one slot toward the member group and aim again once geometry settles.
    hl.dispatch(hl.dsp.focus({ window = "address:" .. me.address }))
    did_focus = true
    hl.dispatch(hl.dsp.window.move({ direction = dir }))
    hyg.oneshot(SETTLE_MS, function()
      attempt(hops + 1)
    end)
  end

  attempt(0)
end

---The first member of a scene block that drifted onto ANOTHER real
---(non-special, id >= 1) workspace, or nil.
---@param scene Scene
---@return HL.Window?
local function first_drifted(scene)
  -- Collect only while the scene is occupied: a scene whose blocks hold no
  -- member on their workspace is dormant — drifting windows there are user
  -- workspace choice, not arrangement debt.
  local occupied = false
  for _, block in ipairs(scene.blocks) do
    for _, w in ipairs(hl.get_windows() or {}) do
      if on_scene(scene, w) and block_for(scene, w) == block and not w.floating then
        occupied = true
      end
    end
  end
  if not occupied then
    return nil
  end
  for _, block in ipairs(scene.blocks) do
    for _, w in ipairs(hl.get_windows() or {}) do
      if block_for(scene, w) == block then
        -- Real workspaces only: special workspaces carry negative ids and
        -- are never a scene's home.
        local ws = w and w.workspace
        local id = ws and tonumber(tostring(ws.id))
        if ws and id and id >= 1 and ws.name ~= scene.name then
          return w
        end
      end
    end
  end
  return nil
end

---The first group-block window not yet folded into its authoritative set.
---@param scene Scene
---@param live table<string, HL.Window>
---@return HL.Window?, SceneBlock?
local function first_stray(scene, live)
  for _, block in ipairs(scene.blocks) do
    if block.group then
      local members = scene.members[block.order]
      for _, w in ipairs(hl.get_windows() or {}) do
        if not w.floating and w.address and w.at and w.size and on_scene(scene, w) and block_for(scene, w) == block then
          if not members[w.address] and not sets_overlap(window_group_set(w, live), members) then
            return w, block
          end
        end
      end
    end
  end
  return nil, nil
end

---The block's leftmost live tile.
---@param scene Scene
---@param block SceneBlock
---@return HL.Window?
local function first_tile(scene, block)
  local best
  for _, w in ipairs(hl.get_windows() or {}) do
    if not w.floating and w.at and w.size and on_scene(scene, w) and block_for(scene, w) == block then
      if not best or w.at.x < best.at.x then
        best = w
      end
    end
  end
  return best
end

---The blocks that have a live tile, in left-to-right geometry order.
---@param scene Scene
---@return SceneBlock[]
local function geometric_blocks(scene)
  local present = {}
  for _, block in ipairs(scene.blocks) do
    if first_tile(scene, block) then
      present[#present + 1] = block
    end
  end
  table.sort(present, function(a, b)
    local ta, tb = first_tile(scene, a), first_tile(scene, b)
    if ta.at.y ~= tb.at.y then
      return ta.at.y < tb.at.y
    end
    return ta.at.x < tb.at.x
  end)
  return present
end

---@param scene Scene
---@return { block: SceneBlock, dir: string }? first block out of order
local function wrong_order(scene)
  if #scene.blocks < 2 then
    return nil
  end
  local present = geometric_blocks(scene)
  local desired = {}
  for _, block in ipairs(scene.blocks) do
    for _, p in ipairs(present) do
      if p == block then
        desired[#desired + 1] = block
      end
    end
  end
  for i = 1, #present do
    if present[i] ~= desired[i] then
      local want = 0
      for j = 1, #desired do
        if desired[j] == present[i] then
          want = j
        end
      end
      return { block = present[i], dir = want > i and "r" or "l" }
    end
  end
  return nil
end

---@param scene Scene
---@return { block: SceneBlock, target: integer, tile: HL.Window }? under/over-sized block
local function wrong_share(scene)
  local tiles = {}
  for _, block in ipairs(scene.blocks) do
    if block.share then
      local tile = first_tile(scene, block)
      if tile then
        tiles[#tiles + 1] = tile
      end
    end
  end
  -- A single tile has nothing to share against; a 0.67 solo group must not
  -- shrink to two thirds of itself.
  if #tiles < 2 then
    return nil
  end
  local left, right = math.huge, -math.huge
  for _, tile in ipairs(tiles) do
    left = math.min(left, tile.at.x)
    right = math.max(right, tile.at.x + tile.size.x)
  end
  local span = right - left
  if span <= 0 then
    return nil
  end
  for _, block in ipairs(scene.blocks) do
    if block.share then
      local tile = first_tile(scene, block)
      local target = math.floor(block.share * span + 0.5)
      if math.abs(tile.size.x - target) > SHARE_TOL * span then
        return { block = block, target = target, tile = tile }
      end
    end
  end
  return nil
end

---One pass of the scene's live geometry (block windows only, floating
---excluded), as a stable string. Two reads a VERIFY_MS apart that agree mean
---the layout is done moving — Hypr animates every correction, and geometry
---measured mid-flight is how corrections loop.
---@param scene Scene
---@param live table<string, HL.Window>
---@return string
local function digest(scene, live)
  local tiles = {}
  for addr, w in pairs(live) do
    if w.at and w.size and on_scene(scene, w) and block_for(scene, w) and not w.floating then
      tiles[#tiles + 1] = addr .. ":" .. w.at.x .. "," .. w.at.y .. ":" .. w.size.x .. "," .. w.size.y
    end
  end
  table.sort(tiles)
  return table.concat(tiles, ";")
end

---Run one corrective action for the scene, then re-verify — ATOMICALLY. The
---step's contract, in order:
---
---  1. The step compares this turn's geometry digest with the previous
---     turn's: unequal reads mean something (animation, user drag, another
---     turn) is still in flight — the turn re-measures instead of acting
---     (this is what makes a workspace switch or a burst of moves settle
---     instead of wiggle).
---  2. Pick the highest-priority unsettled invariant (collect home, join,
---     order, share), commit it once, and re-verify.
---  3. Never run the same correction twice in a row: if the geometry did not
---     change after a correction, re-picking it would oscillate — the pass
---     ends instead and the scene keeps the user's arrangement.
---  4. Turn-bounded throughout (MAX_TURNS): no chain of timers can loop.
---@param scene Scene
local function realize(scene)
  if scene.busy then
    return
  end
  scene.busy = true
  local turns = 0

  local function step()
    turns = turns + 1
    if turns > MAX_TURNS then
      scene.busy = false
      return
    end

    local live = live_map()
    local now = digest(scene, live)
    if not scene.last_digest or scene.last_digest ~= now then
      -- Nothing to measure against yet, or something moved since the last
      -- read (animation, user drag, another turn): re-measure next tick,
      -- never correct mid-flight. Acting on one reading alone is exactly
      -- how corrections loop.
      scene.last_digest = now
      hyg.oneshot(VERIFY_MS, step)
      return
    end
    scene.last_digest = now
    -- Collect a drifted member home first. A scene is the workspace's
    -- arrangement: a block member whose scene is occupied comes back, and
    -- the reorganization proceeds as if it had always been there
    -- (LEO-245's bare minimum).
    local drift = first_drifted(scene)
    if drift then
      local prev = hl.get_active_window()
      if drift.floating then
        -- A floated stray re-tiles before the move, or the arrangement
        -- below cannot count it (floating windows are not members of the
        -- layout the scene realizes into).
        hl.dispatch(hl.dsp.focus({ window = "address:" .. drift.address }))
        hl.dispatch(hl.dsp.window.float())
      end
      local fix = "collect:" .. drift.address
      if scene.last_fix == fix then
        scene.busy = false
        return
      end
      scene.last_fix = fix
      hl.dispatch(hl.dsp.window.move({
        workspace = "name:" .. scene.name,
        window = "address:" .. drift.address,
      }))
      restore_focus(prev, drift.address)
      hyg.oneshot(VERIFY_MS, step)
      return
    end

    local stray, stray_block = first_stray(scene, live)
    if stray then
      scene.last_fix = nil
      fold_stray(stray, scene.members[stray_block.order], function()
        hyg.oneshot(VERIFY_MS, step)
      end)
      return
    end

    local order = wrong_order(scene)
    if order then
      local tile = first_tile(scene, order.block)
      local fix = "order:" .. order.block.order .. ":" .. tile.address
      if scene.last_fix == fix then
        scene.busy = false
        return
      end
      scene.last_fix = fix
      local prev = hl.get_active_window()
      hl.dispatch(hl.dsp.focus({ window = "address:" .. tile.address }))
      hl.dispatch(hl.dsp.window.move({ direction = order.dir }))
      restore_focus(prev, tile.address)
      hyg.oneshot(VERIFY_MS, step)
      return
    end

    local share = wrong_share(scene)
    if share then
      local fix = "share:" .. share.block.order .. ":" .. share.target
      if scene.last_fix == fix then
        scene.busy = false
        return
      end
      scene.last_fix = fix
      local prev = hl.get_active_window()
      hl.dispatch(hl.dsp.focus({ window = "address:" .. share.tile.address }))
      hl.dispatch(hl.dsp.window.resize({ x = share.target, y = share.tile.size.y }))
      restore_focus(prev, share.tile.address)
      hyg.oneshot(VERIFY_MS, step)
      return
    end

    -- Settled: nothing left to correct.
    scene.last_digest = nil
    scene.last_fix = nil
    scene.busy = false
  end

  step()
end

---The scene whose blocks `w` belongs to, by workspace default_name, or nil.
---@param w HL.Window
---@return string? the scene whose scene window `w` is, if any
local function scene_for(w)
  if not w or not w.workspace then
    return nil
  end
  local scene = scenes[w.workspace.name]
  if scene and block_for(scene, w) then
    return scene.name
  end
  return nil
end

---Arm one realize pass for `key`. Scheduling is a GATE, not a queue: a burst
---of events (workspace switches, a stream of cross-workspace moves) collapses
---into one pass per SETTLE window, and a scene mid-realize coalesces into the
---verify chain it is already running — corrections read the compositor's state
---at dispatch time, so a pass that starts a beat later fixes the same reality.
---Without the gate, a stream of user moves chains realize storm after realize
---storm, and the desk dances.
---@param key string
local function schedule_realize(key)
  local scene = scenes[key]
  if not scene or scene.busy or scene.pending then
    return
  end
  scene.pending = true
  hyg.oneshot(SETTLE_MS, function()
    scene.pending = false
    realize(scene)
  end)
end

build()

-- Seed: self-heal scenes already populated when the config reloads (the
-- re-registered handlers miss the windows that opened before this require).
for _, w in ipairs(hl.get_windows() or {}) do
  local key = scene_for(w)
  if key then
    schedule_realize(key)
  end
end

hl.on("window.open", function(w)
  local key = w and scene_for(w)
  if key then
    schedule_realize(key)
  end
end)

hl.on("window.close", function(w)
  local key = w and w.address and scene_for(w)
  if key then
    schedule_realize(key)
  end
end)

-- Cross-workspace moves are map/close in law (LEO-245's bare minimum): the
-- moved window's scene re-realizes where it arrived. Narrow on purpose — a
-- move into one scene must not re-arrange every other scene — and the gate
-- collapses a stream of moves into one pass each.
hl.on("window.move_to_workspace", function(w)
  local key = w and w.address and scene_for(w)
  if key then
    schedule_realize(key)
  end
end)

-- Re-entering a scene workspace restores its arrangement: whatever fiddling
-- happened while it was behind the user (and whatever moved home) is
-- rechecked, so the geometry users come back to is the scene's, not drift.
hl.on("workspace.active", function()
  local ws = hl.get_active_workspace()
  if not ws then
    return
  end
  local scene = scenes[ws.name]
  if scene then
    schedule_realize(ws.name)
  end
end)

local M = {}

---Scene name owning this workspace, or nil.
---@param ws { id: integer|string }?
---@return string?
function M.active(ws)
  if not ws or not ws.name then
    return nil
  end
  return scenes[ws.name] and ws.name or nil
end

---Run the realize loop for the named scene.
---@param name string
function M.realize(name)
  local scene = scenes[name]
  if scene then
    realize(scene)
  end
end

---Leftmost live tile of the block matching `match`, or nil.
---@param name string
---@param match string|{ class: string }
---@return HL.Window?
function M.tile(name, match)
  local scene = scenes[name]
  local cls = type(match) == "table" and match.class or match
  if not scene or type(cls) ~= "string" then
    return nil
  end
  local block = block_for(scene, { class = cls })
  if not block then
    return nil
  end
  return first_tile(scene, block)
end

return M
