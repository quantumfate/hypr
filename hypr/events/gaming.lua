-- Gaming scene: keep exactly one media browser beside the Dofus group.
--
-- The Dofus clients form one locked Hyprland group (windowrules.lua), and
-- LEO-230 reserves the region to its right for a `zen-media` browser. This
-- module is the scene's *lifecycle* only; the region and the group join are
-- the scene engine's (hypr/events/scene.lua, LEO-245):
--
--   * the first Dofus window spawns the browser (same Media profile, the
--     `apps.media_scene` command);
--   * it never spawns a second while one is already open (or on its way);
--   * when the last Dofus window leaves, the browser is closed.

local DOFUS_CLASS = "Dofus.x64"

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
