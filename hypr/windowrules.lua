-- TODO: implement option 1 if implemented
-- https://github.com/hyprwm/Hyprland/discussions/15901

local windowrule = require("hypr.lib.windowrule")

-- Class strings come from config.apps so a launch command and its window rules
-- can never drift apart. Only apps whose class is a plain literal are sourced
-- here; regex alternations covering variants we do not launch stay hardcoded.
local apps = config.apps

windowrule.tag_props({
  { initial_class = "([fF]irefox|zen|zen-twilight|zen-beta)" },
}, "+default-browser")

windowrule.tag_props({
  { initial_class = "(" .. apps.media_browser.class .. ")" },
}, "+media-browser")

-- Terminals are deliberately absent here: a terminal opens on the workspace you
-- launched it from. Pinning them to `code` made a second project window
-- impossible to keep anywhere else. `,proj.sh` places its own windows instead,
-- with a per-launch exec rule (`code` by default, or the project's own
-- `workspace =`) — so a project starts where it belongs and still moves freely
-- afterwards.
windowrule.tag_props({
  { tag = "default-browser" },
  { initial_class = "(" .. apps.dev_browser.class .. ")" },
}, "+code")

windowrule.tag_set_effects("code", {
  static = { workspace = "name:code" },
})

windowrule.tag_props({
  { initial_class = "(md.obsidian.Obsidian)" },
  { initial_class = "(linear)" },
}, "+creative")

windowrule.tag_set_effects("creative", {
  static = { workspace = "name:creative" },
})

windowrule.tag_props({
  { initial_class = "(" .. apps.mail.class .. ")" },
  { initial_class = "(" .. apps.password_manager.class .. ")" },
}, "+proton")

windowrule.tag_set_effects("proton", {
  static = { workspace = "name:proton" },
})
windowrule.tag_props({
  { initial_class = "(Archon App)" },
  { initial_class = "(ckb-next)" },
  { initial_class = apps.package_manager_ui.class },
}, "misc")

windowrule.tag_set_effects("misc", {
  static = { workspace = "name:misc" },
})

windowrule.tag_props({
  { initial_class = "(Alacritty|kitty|ghostty|foot)" },
}, "+terminal")

-- `,proj.sh`'s picker. A terminal rather than a layer surface, so that it lands
-- where you are and takes focus by itself — which is exactly what rofi could
-- not be told to do. No workspace here on purpose: it belongs on the workspace
-- you pressed the key from, unlike the project window it goes on to open.
windowrule.tag_props({
  { initial_class = "(Proj-Picker)" },
}, "+project-picker")

windowrule.tag_set_effects("project-picker", {
  static = { workspace = "name:code", float = true, center = true, fullscreen_state = "0 0" },
  dynamic = {
    min_size = { "monitor_w * 0.4", "monitor_h * 0.45" },
    max_size = { "monitor_w * 0.4", "monitor_h * 0.45" },
  },
})

windowrule.tag_props({
  { initial_title = "(Picture.?in.?[Pp]icture)" },
  { tag = "media-browser", title = "^(Picture-in-Picture)$" },
  { tag = "default-browser", title = "^(Picture-in-Picture)$" },
}, "+pip")

windowrule.tag_set_effects("pip", {
  static = {
    float = true,
    size = { "window_w * 0.2", "monitor_h * 0.2" },
    keep_aspect_ratio = true,
    border_size = 0,
  },
  dynamic = {
    opacity = "1 override 1 override",
    move = { "window_w * 0.7", "monitor_h * 0.7" },
  },
})

windowrule.tag_props({

  { initial_class = "(zen|zen-twilight|zen-beta)", title = "(Library)" },
  { initial_class = "(zen|zen-twilight|zen-beta)", title = "Add bookmark folder" },
  { initial_class = [[(org\.keepassxc\.KeePassXC)]], title = "(Unlock Database - KeePassXC)" },
  { initial_class = apps.package_manager_ui.class },
  { initial_class = "(wdisplays)" },
}, "+large-floating-window")

windowrule.tag_set_effects("large-floating-window", {
  static = { float = true, center = true, fullscreen_state = "0 0" },
  dynamic = {
    min_size = { "monitor_w * 0.7", "monitor_h * 0.7" },
    -- max_size = { "monitor_w * 0.7", "monitor_h * 0.7" },
    persistent_size = true,
  },
})

windowrule.tag_props({
  {
    initial_class = "(xdg-desktop-portal-hyprland|xdg-desktop-portal-gtk|sublime_text|DesktopEditors)",
    title = "(Open.*Files?|Save.*Files?|Save.*As|All Files|Save)",
  },
  {
    initial_class = [[(protonvpn-app|Impala|About|Wiremix|com.gabm.satty|Calos|TUI.float|]]
      .. [[io\.github\.Qalculate\.qalculate-qt)]],
  },
  { initial_class = "(Ranger-tui|Wiremix-tui|Btop-tui|Parui-tui|Blue-tui)" },
  { initial_class = "(zen|zen-twilight|zen-beta)", title = "(Library)" },
  { initial_class = "(zen|zen-twilight|zen-beta)", title = "Add bookmark folder" },
  { initial_class = [[(org\.keepassxc\.KeePassXC)]], title = "(Unlock Database - KeePassXC)" },
  { initial_class = "com.github.hluk.copyq" },
  { initial_class = apps.package_manager_ui.class },
  { initial_class = "ckb-next" },
}, "+medium-floating-window")

windowrule.tag_set_effects("medium-floating-window", {
  static = { float = true, center = true, fullscreen_state = "0 0" },
  dynamic = {
    min_size = { "monitor_w * 0.4", "monitor_h * 0.4" },
    max_size = { "monitor_w * 0.5", "monitor_h * 0.5" },
    persistent_size = true,
  },
})

windowrule.tag_props({
  { initial_class = "(" .. apps.password_manager.class .. "|" .. apps.mail.class .. ")" },
  { initial_class = "com.github.hluk.copyq" },
  { initial_class = "signal" },
}, "+exclude-from-screenshare")

windowrule.tag_set_effects("exclude-from-screenshare", {
  dynamic = { no_screen_share = true },
})

windowrule.tag_set_effects("media-browser", {
  static = { workspace = "name:media" },
})

-- The gaming scene's own zen instance (apps.media_scene, LEO-230): pinned to
-- name:gaming so it lands beside the Dofus group wherever it is spawned. Its
-- group guard is the scene block's (`guard = "deny"`), emitted by
-- hypr/scene/compile.lua — the scene decides grouping once, for every class it
-- names. The browser opens automatically with the first Dofus window and
-- closes with the last — see hypr/events/gaming.lua, which is why there is no
-- bar-side browser for this scene.
windowrule.tag_props({
  { initial_class = "(" .. apps.media_scene.class .. ")" },
}, "+gaming-media")

windowrule.tag_set_effects("gaming-media", {
  static = { workspace = "name:gaming" },
})

local not_eso_launcher = { class = "steam_app_default", title = "[^(Zenimax Online Studios Launcher)]" }
local eso_launcher = { class = "steam_app_default", title = "Zenimax Online Studios Launcher" }
local arbitrary_steam_app = { class = [[steam_app_\d+]] }
local default_steam_app = { class = "steam_app_default" }
local steam = { class = "(steam)" }
local lutris = { class = "net.lutris.Lutris" }

-- Gaming
windowrule.tag_props({
  arbitrary_steam_app,
  default_steam_app,
  not_eso_launcher,
}, "+gaming")

windowrule.tag_set_effects("gaming", {
  -- These classes are in the gaming scene's `barred` list (conf/hosts/), so
  -- the bar that keeps auto_group from swallowing a game into the Dofus tab
  -- strip is emitted by hypr/scene/compile.lua rather than repeated here.
  static = {
    workspace = "name:gaming",
    suppress_event = "activate activatefocus",
    fullscreen_state = "2 3",
  },
})

windowrule.tag_props({
  steam,
  eso_launcher,
  lutris,
}, "+launcher")

windowrule.tag_props({ lutris }, "+left-float")
windowrule.tag_props({ eso_launcher }, "+right-float")

windowrule.tag_set_effects("left-float", {
  static = {
    move = { 200, 200 },
  },
})

windowrule.tag_set_effects("right-float", {
  static = {
    move = { "(monitor_w / 2)", 100 },
  },
})

windowrule.tag_set_effects("launcher", {
  static = {
    workspace = "special:launcher",
    fullscreen_state = "0 1",
  },
})

hl.window_rule({ match = lutris, size = { "monitor_w * 0.35", "monitor_h * 0.8" } })

hl.window_rule({ match = { class = [[steam_app_\d+]] }, fullscreen_state = "2 2" })
hl.window_rule({ match = { class = "(steam)", title = "Friends List" }, move = { 300, 400 }, float = true })
hl.window_rule({ match = { class = "(steam)", title = "Launching..." }, move = { 600, 600 } })
hl.window_rule({ match = { title = "(Steam Settings)" }, float = true })

-- Steam notification toasts
windowrule.tag_props({
  { class = "^(steam)$", title = "^(notificationtoasts)" },
}, "+steam-toast")

windowrule.tag_set_effects("steam-toast", {
  static = { no_initial_focus = true, pin = true },
})

-- Dofus / Ankama
--
-- The group itself is declared by the gaming scene, not here: the block
-- carries `group = true`, and hypr/scene/compile.lua emits the `set always`
-- that puts every Dofus client in one group every time. The runtime engine
-- then holds that invariant against auto_group races — one decision, asserted
-- at both ends, instead of two rules that could disagree.
-- The guard against foreign windows is NOT `lock` here — `lock always invade`
-- was tried (LEO-234) and live-regressed the group: the lock also rejects
-- later Dofus clients, and `invade` did not reliably override it, so a third
-- client landed in a group of its own. The guard is instead enforced from the
-- other side: every window that could land on name:gaming is denied or barred
-- by its own rule (the scene browser is `deny`, the gaming tag and the Ankama
-- overlay are `barred`), which keeps the group pure without touching the
-- Dofus clients themselves. A future OBS
-- scene (LEO-232) still gets one stable tile to crop to instead of eight
-- floating windows — LEO-234's guard: non-Dofus windows open beside the group,
-- never inside it. The group's tile is what the roster addresses
-- (hypr/services/dofus/team.lua reads it off any member's `.group`, not a
-- standalone window list), and its groupbar is now the taskbar — LEO-221
-- dropped the bar's own Dofus strip because a group already names its members
-- and marks the focused one.
hl.window_rule({
  match = { initial_class = "Dofus.x64" },
  workspace = "name:gaming",
  center = true,
  content = "game",
  opacity = "1.0 override",
  no_anim = true,
  suppress_event = "fullscreen",
})
hl.window_rule({
  match = { initial_class = "Ankama Launcher" },
  workspace = "special:ankama",
})
hl.window_rule({
  match = { class = "Ankama Launcher", title = "overlay" },
  workspace = "name:gaming",
  -- The bar that keeps this overlay out of the Dofus group is the gaming
  -- scene's (`barred` in conf/hosts/), emitted by hypr/scene/compile.lua.
  float = true,
  center = true,
  tag = "+floating-window",
})

-- Comms
windowrule.tag_props({
  { class = "(vesktop|whatsapp-electron|signal)" },
}, "+comms")

windowrule.tag_set_effects("comms", {
  static = { suppress_event = "activate activatefocus", workspace = "special:comms" },
})

-- Media apps (opacity fix)
windowrule.tag_props({
  {
    class = "^(zoom|vlc|mpv|mp4|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv|"
      .. "org.gnome.NautilusPreviewer)$",
  },
}, "+media-app")

windowrule.tag_set_effects("media-app", {
  dynamic = { opacity = "1 1" },
})

-- Tile overrides
windowrule.tag_props({
  { class = [[^(org\.wezfurlong\.wezterm)$]] },
  { class = "^(gnome-control-center)$" },
  { class = "^(pavucontrol)$" },
  { class = "^(nm-connection-editor)$" },
  { tag = "chromium-based-browser" },
}, "+tile-override")

windowrule.tag_set_effects("tile-override", {
  static = { tile = true },
})

-- Float overrides
windowrule.tag_props({
  { class = [[^(org\.gnome\.Calculator)$]] },
  { class = "^(gnome-calculator|galculator|blueman-manager|zoom|xdg-desktop-portal)$" },
  { class = [[^(org\.gnome\.Nautilus)$]] },
  { class = "(ffplay|clipse|" .. apps.terminal_float.class .. ")" },
  { class = "(" .. apps.file_manager.class .. ")" },
  { class = "(" .. apps.package_manager_tui.class .. ")" },
  { tag = "launcher" },
}, "+float-override")

windowrule.tag_set_effects("float-override", {
  static = { float = true },
})

hl.window_rule({ match = { class = "(clipse)" }, size = { 800, 600 } })
-- hl.window_rule({ match = { class = "(Kitty-Float)" }, size = { 1000, 800 }, center = true })
--
windowrule.tag_props({
  { initial_class = apps.bluetooth_manager.class },
  { initial_class = apps.file_manager.class },
  { initial_class = apps.terminal_float.class },
  { initial_class = apps.volume_control.class },
}, "+floating-terminal-app")

windowrule.tag_set_effects("floating-terminal-app", {
  static = {
    float = true,
    size = { "monitor_w * 0.5", "monitor_h * 0.8" },
    center = true,
  },
  dynamic = {},
})

-- Gnome rounding
windowrule.tag_props({
  { class = [[^(org\.gnome\.)]] },
}, "+gnome-app")

windowrule.tag_set_effects("gnome-app", {
  dynamic = { rounding = 12 },
})

hl.window_rule({
  name = "feh",
  match = { initial_class = "feh" },
  workspace = "special:feh",
  float = true,
  content = "photo",
  center = true,
  rounding = 0,
  opacity = "1 override 1 override",
})

windowrule.tag_props({ { initial_class = "([Ss]potify)" } }, "+music")
windowrule.tag_set_effects("music", { static = { workspace = "special:music" } })

-- Terminals stack, the browser does not.
--
-- A coding workspace grows one browser and however many project windows the day
-- needs. Left as plain tiles, the fifth terminal makes every window useless.
-- Grouped, they are one tile with a tab strip: the split stays two-way whatever
-- the count, and the groupbar (styled in conf.lua) says which one is in front.
--
-- The grouping itself is the `code` scene's first block (conf/hosts/):
-- `Kitty-Main` and `Proj-*` are its classes, and hypr/scene/compile.lua emits
-- the `set always` for both. It is `set always` rather than plain `set`
-- because the default only groups a window the first time, and the point here
-- is that it holds for every project window, every time.
--
-- The bar below is wider than any one scene — it keeps a browser out of the
-- focused group on every workspace, not only the coding one — so it stays
-- here as global policy.
for _, cls in ipairs({
  "([fF]irefox|zen|zen-twilight|zen-beta)",
  config.apps.dev_browser.class,
  config.apps.media_browser.class,
}) do
  hl.window_rule({ name = "no-group-" .. cls, match = { class = cls }, group = "barred" })
end

-- Column widths on the scrolling layout (still reachable on the layout cycle).
--
-- The point of scrolling here is that window sizes are DECLARED, not dragged: a
-- window opens at the width its job deserves and stays there. A project
-- terminal and a browser sharing the panel should not get the same half each —
-- the terminal is where the work happens and the browser is a reference.
--
-- The two together come to 1.0, so a terminal and a browser side by side fill
-- the panel exactly. Alone, each leaves the rest of the tape empty, which is
-- what `fullscreen_on_one_column = false` is for.
local scrolling_widths = {
  -- Two thirds for the work, one third for the reference. A third of 5120px is
  -- ~1700px, which is still a desktop site with no wasted margin, and it leaves
  -- the terminal the width it actually needs.
  -- Project terminals (`Proj-<name>`, one class per project) and the plain one.
  { match = { class = config.apps.project.class }, width = 0.67 },
  { match = { class = config.apps.terminal.class }, width = 0.67 },
  { match = { class = "([fF]irefox|zen|zen-twilight|zen-beta)" }, width = 0.33 },
  { match = { class = config.apps.dev_browser.class }, width = 0.33 },
  -- Reading and reference sit narrower still; two fit beside a terminal.
  { match = { class = config.apps.file_manager.class }, width = 0.33 },
}

for _, rule in ipairs(scrolling_widths) do
  hl.window_rule({
    name = "scrolling-width-" .. rule.match.class,
    match = rule.match,
    scrolling_width = rule.width,
  })
end

-- fix the regression of maximized windows overshadowing other windows in a WS
-- TODO: this wild cald potentially needs further narrowing
hl.window_rule({
  match = {
    class = ".*",
  },
  suppress_event = "maximize",
})

-- The scene layer's rules come last: `group` is decided by the scene that
-- names the class (hypr/scene/compile.lua), and a later rule is the one that
-- stands. Emitting here — rather than where the scenes are read — keeps every
-- window rule in the file that owns window rules.
require("hypr.scene.compile").emit(require("hypr.scene.spec").load())
