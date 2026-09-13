-- Gaming scene: keep exactly one media browser beside the Dofus group.
--
-- The Dofus clients form one locked Hyprland group (windowrules.lua), and
-- LEO-230 reserves the region to its right for a `zen-media` browser. This
-- module is the scene's lifecycle:
--
--   * the first Dofus window spawns the browser (same Media profile, the
--     `apps.media_scene` command);
--   * each later Dofus window is folded into that group once its tiled
--     geometry settles (schedule_group_merge below);
--   * it never spawns a second while one is already open (or on its way);
--   * when the last Dofus window leaves, the browser is closed.
--
-- The browser is pinned to name:gaming and barred from groups by its window
-- rule, so the group reservation holds; the resting split between the two
-- tiles comes from the workspace's layout_opts (see the gaming workspace
-- specs in hyprland.lua).

local hyg = require("hypr.lib.hypr")

local DOFUS_CLASS = "Dofus.x64"
-- How long after a Dofus window maps until its tiled geometry (`at`/`size`,
-- GEOMETRIC_GOAL) is final and a direction can be aimed. The merge itself
-- happens at `window.move into_group` time, so only the geometry's accuracy
-- depends on this delay, not the join.
local MERGE_SETTLE_MS = 100

-- Membership is tracked by address, captured at window.open (when live fields
-- are readable) and forgotten at window.close (when they may not be). Only
-- windows that mapped onto a gaming workspace are ever recorded.
local dofus_on_scene = {}
local media_on_scene = {}

-- True between the moment we dispatch the spawn and the moment the browser's
-- open event lands: stops a second Dofus client racing in from spawning a
-- duplicate browser before the first one registers.
local spawn_pending = false

---@return string?
local function media_class()
  return config.apps and config.apps.media_scene and config.apps.media_scene.class
end

---@param w HL.Window|nil
---@return boolean whether the window's workspace carries the gaming scene
local function on_scene(w)
  local ws = w and w.workspace
  if not ws then
    return false
  end
  for _, spec in ipairs(config.host.workspaces.workspace_specs) do
    if spec.default_name == "gaming" and tostring(spec.workspace) == tostring(ws.id) then
      return true
    end
  end
  return false
end

local function spawn_media_browser()
  local cmd = config.apps.media_scene.cmd
  if not cmd or cmd == "" then
    return
  end
  spawn_pending = true
  hl.dispatch(hl.dsp.exec_cmd("uwsm app -- " .. cmd))
end

---@param address string
local function close_window(address)
  hl.dispatch(hl.dsp.window.close({ window = "address:" .. address }))
end

---@param w HL.Window
---@return number, number window center
local function center(w)
  return w.at.x + w.size.x / 2, w.at.y + w.size.y / 2
end

---@param a HL.Window
---@param b HL.Window
---@return number squared euclidean distance between the two centers
local function center_distance_sq(a, b)
  local ax, ay = center(a)
  local bx, by = center(b)
  local dx, dy = ax - bx, ay - by
  return dx * dx + dy * dy
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

---HL.Group.members is a bare HL.Window when the group holds exactly one,
---otherwise an array — normalize to an array (same shape team.lua reads).
---@param group HL.Group
---@return HL.Window[]
local function group_members(group)
  local members = group.members
  if members == nil then
    return {}
  end
  if members.title then
    return { members }
  end
  return members
end

---@param w HL.Window
---@return boolean whether the window already shares a group with another member
local function in_multi_member_group(w)
  local group = w.group
  return group ~= nil and #group_members(group) > 1
end

---Fold `new_window` into the existing Dofus group once its tiled geometry
---settles. windowrules make every Dofus.x64 window its own "set always" group,
---and Hyprland only auto-joins a new window into the *focused* group at map
---time — but Dofus clients launch from the ankama scratchpad, so the merge
---never fires and every client is left in its own group. The scheduler aims
---`window.move into_group` at the nearest pre-existing member (the primitive
---takes a direction, not a target address); with no member it does nothing —
---the first window is the seed of the group.
---@param new_window HL.Window
local function schedule_group_merge(new_window)
  local candidates = {}
  for address in pairs(dofus_on_scene) do
    if address ~= new_window.address then
      candidates[#candidates + 1] = address
    end
  end
  if #candidates == 0 then
    return
  end

  hyg.oneshot(MERGE_SETTLE_MS, function()
    local live = {}
    for _, w in ipairs(hl.get_windows() or {}) do
      live[w.address] = w
    end

    local target = live[new_window.address]
    if not target or not target.at or not target.size then
      return
    end
    -- Hyprland may have merged it after all (focus was in the group at map
    -- time); a settled multi-member group wants no second move.
    if in_multi_member_group(target) then
      return
    end

    local nearest, nearest_dist = nil, nil
    for _, address in ipairs(candidates) do
      local member = live[address]
      if member and member.at and member.size then
        local dist = center_distance_sq(target, member)
        if nearest_dist == nil or dist < nearest_dist then
          nearest, nearest_dist = member, dist
        end
      end
    end
    if not nearest then
      return
    end

    hl.dispatch(hl.dsp.window.move({
      into_group = direction_to(target, nearest),
      window = "address:" .. target.address,
    }))
  end)
end

-- Seed the registries from what is already open (config reloads re-register
-- every handler, and the scene must not re-spawn a browser that exists).
for _, w in ipairs(hl.get_windows() or {}) do
  if on_scene(w) then
    if w.class == media_class() then
      media_on_scene[w.address] = true
    elseif w.class == DOFUS_CLASS then
      dofus_on_scene[w.address] = true
    end
  end
end

hl.on("window.open", function(w)
  if not w then
    return
  end
  if w.class == media_class() then
    if on_scene(w) then
      media_on_scene[w.address] = true
      spawn_pending = false
    end
    return
  end
  if w.class == DOFUS_CLASS and on_scene(w) then
    dofus_on_scene[w.address] = true
    if not next(media_on_scene) and not spawn_pending then
      spawn_media_browser()
    end
    schedule_group_merge(w)
  end
end)

hl.on("window.close", function(w)
  local address = w and w.address
  if not address then
    return
  end

  local was_dofus = dofus_on_scene[address] ~= nil
  local was_media = media_on_scene[address] ~= nil
  dofus_on_scene[address] = nil
  media_on_scene[address] = nil
  if not was_dofus and not was_media then
    return
  end

  -- Last Dofus window out: close the scene's browser. A media window closing
  -- on its own is respected (the browser re-spawns only when a Dofus window
  -- opens into an empty scene).
  if was_dofus and not next(dofus_on_scene) then
    for media_address in pairs(media_on_scene) do
      close_window(media_address)
    end
  end
end)
