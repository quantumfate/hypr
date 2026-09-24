local Store = require("hypr.lib.store")
local theme = Store.define("theme")

-- The desk-wide dial: 0 is presentation mode (everything opaque, whatever the
-- roles below say), 1 gives each role the transparency it was designed with.
-- Named for what you turn up, because a dial called `opacity` that you turn
-- DOWN to get transparency reads backwards every time.
---@return number
local function dial()
  return theme:get("transparency") or 1.0
end

---@param floor number this role's opacity with the dial fully up
---@return number
local function role_opacity(floor)
  return 1 - (1 - floor) * dial()
end

-- Class -> role, opacity floor. Only roles that get transparency need an
-- entry; anything absent here is left at conf.lua's opaque default, which is
-- exactly right for browsers, media players, games and image viewers — none
-- of them may show the desktop through a frame of decoded pixels.
--
-- Terminals/editor sit closest to the desktop (mostly text, lots of empty
-- cell background) so they read fine thinned out a little; file/process
-- managers are text-and-chrome too and get the same treatment.
local roles = {
  terminal = { class = config.apps.terminal.class, floor = 0.94 },
  terminal_float = { class = config.apps.terminal_float.class, floor = 0.94 },
  project = { class = config.apps.project.class, floor = 0.94 },
  file_manager = { class = config.apps.file_manager.class, floor = 0.93 },
  volume_control = { class = config.apps.volume_control.class, floor = 0.93 },
  bluetooth_manager = { class = config.apps.bluetooth_manager.class, floor = 0.93 },
  package_manager_tui = { class = config.apps.package_manager_tui.class, floor = 0.93 },
}

for name, role in pairs(roles) do
  hl.window_rule({
    name = "role-opacity-" .. name,
    match = { class = "(" .. role.class .. ")" },
    opacity = tostring(role_opacity(role.floor)) .. " override",
  })
end

local opaque_media_browser = hl.window_rule({
  name = "opaque-media-browser",
  enabled = false,
  match = { tag = "media-browser" },
  opacity = "1.0 override",
})

-- The dofus browser is a browser like the other two: video and text read
-- wrong through translucency, so the same focus-time opacity override applies.
local opaque_dofus_browser = hl.window_rule({
  name = "opaque-dofus-browser",
  enabled = false,
  match = { tag = "dofus-browser" },
  opacity = "1.0 override",
})

local opaque_default_browser = hl.window_rule({
  name = "opaque-default-browser",
  enabled = false,
  match = { tag = "default-browser" },
  opacity = "1.0 override",
})

---@param w HL.Window
---@param tag string
---@return boolean
local function is_tagged_browser(w, tag)
  if type(w.tags) == "table" then
    if
      require("hypr.lib.fn").any(function(p)
        return p == tag
        ---@diagnostic disable-next-line: param-type-mismatch
      end, w.tags) or w.tags == tag
    then
      return true
    end
  end
  return false
end

---@param w HL.Window
---@param w_rule HL.WindowRule
local function toggle_media_opacity(w, w_rule)
  if w.title:lower():find("crunchyroll") or w.title:lower():find("twitch") or w.title:lower():find("youtube") then
    w_rule:set_enabled(true)
  else
    w_rule:set_enabled(false)
  end
end

hl.on(
  "window.update_rules",
  ---@param w HL.Window
  function(w)
    if is_tagged_browser(w, "media-browser*") then
      toggle_media_opacity(w, opaque_media_browser)
    end
    if is_tagged_browser(w, "dofus-browser*") then
      toggle_media_opacity(w, opaque_dofus_browser)
    end
    if is_tagged_browser(w, "default-browser*") then
      toggle_media_opacity(w, opaque_default_browser)
    end
  end
)
