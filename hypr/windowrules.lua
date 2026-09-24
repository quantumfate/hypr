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

windowrule.tag_props({
  { initial_class = "(" .. apps.dofus_browser.class .. ")" },
}, "+dofus-browser")

windowrule.tag_props({
  { initial_class = "(" .. apps.pokemon_left_browser.class .. ")" },
}, "+pokemon-left-browser")

windowrule.tag_props({
  { initial_class = "(" .. apps.pokemon_right_browser.class .. ")" },
}, "+pokemon-right-browser")

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
  static = { workspace = "name:obsidian-linear" },
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
  { initial_class = apps.package_manager_ui.class },
}, "misc")

windowrule.tag_props({
  { initial_class = "(Alacritty|kitty|ghostty|foot)" },
}, "+terminal")

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
  { initial_class = apps.package_manager_ui.class },
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

-- The dofus browser has its own profile, so its class is its own and the pin
-- needs no claim to undo it: it lands on the gaming workspace and stays.
windowrule.tag_set_effects("dofus-browser", {
  static = { workspace = "name:dofus" },
})

-- The pokemon desk's two named profiles are one browser each, with their own
-- classes. Like dofus's, each class is its own scope and the pin needs no
-- claim to undo it: both land on the pokemon workspace where their slot
-- blocks wait.
windowrule.tag_set_effects("pokemon-left-browser", {
  static = { workspace = "name:pokemon" },
})

windowrule.tag_set_effects("pokemon-right-browser", {
  static = { workspace = "name:pokemon" },
})

-- The nested e2e host models the shared-profile desk (LEO-412): the fixture's
-- "claim-browser" scene is the pin target for the shared e2e-shared class —
-- the same arrangement as +media-browser pinning the zen profile to media —
-- so a spawned companion opens on claim-browser and the engine's claim step
-- stamps the claim-dofus slot, letting home route it back to its scene. A
-- real host never names this class; the rule is inert everywhere else.
if os.getenv("QF_HOST") == "e2e" then
  windowrule.tag_props({ { initial_class = "(e2e%-shared)" } }, "+e2e-shared-pin")
  windowrule.tag_set_effects("e2e-shared-pin", {
    static = { workspace = "name:claim-browser" },
  })
end

local not_eso_launcher = { class = "steam_app_default", title = "[^(Zenimax Online Studios Launcher)]" }
local eso_launcher = { class = "steam_app_default", title = "Zenimax Online Studios Launcher" }
local arbitrary_steam_app = { class = [[steam_app_\d+]] }
local default_steam_app = { class = "steam_app_default" }

-- Gaming
windowrule.tag_props({
  arbitrary_steam_app,
  default_steam_app,
  not_eso_launcher,
}, "+gaming")

windowrule.tag_set_effects("gaming", {
  -- These classes are in the steam-games scene's `barred` list (conf/hosts/),
  -- so the bar that keeps auto_group from swallowing a game into the Dofus
  -- tab strip is emitted by hypr/scene/compile.lua rather than repeated here.
  static = {
    workspace = "name:steam-games",
    suppress_event = "activate activatefocus",
    fullscreen_state = "2 3",
  },
})

-- Steam and Lutris live on shelves (hypr/lib/drawer.lua, rules at the end of
-- this file). The ESO launcher is Steam's, so it opens on the Steam shelf.
hl.window_rule({ match = eso_launcher, workspace = "special:shelf-steam", float = true, center = true })

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
-- The group itself is declared by the dofus scene, not here: the block
-- carries `group = true`, and hypr/scene/compile.lua emits the `set always`
-- that puts every Dofus client in one group every time. The runtime engine
-- then holds that invariant against auto_group races — one decision, asserted
-- at both ends, instead of two rules that could disagree.
-- The guard against foreign windows is NOT `lock` here — `lock always invade`
-- was tried (LEO-234) and live-regressed the group: the lock also rejects
-- later Dofus clients, and `invade` did not reliably override it, so a third
-- client landed in a group of its own. The guard is instead enforced from the
-- other side: every window that could land on name:dofus is denied or barred
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
  workspace = "name:dofus",
  center = true,
  content = "game",
  opacity = "1.0 override",
  no_anim = true,
  suppress_event = "fullscreen",
})
hl.window_rule({
  match = { class = "Ankama Launcher", title = "overlay" },
  workspace = "name:dofus",
  -- The bar that keeps this overlay out of the Dofus group is the dofus
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
  -- Signal and Vesktop live on shelves (hypr/lib/drawer.lua); the tag only
  -- keeps them from stealing focus when a message arrives.
  static = { suppress_event = "activate activatefocus" },
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

-- feh opens floating, centred, and capped to the same frame a tiled window
-- would get -- the monitor minus default_gaps' outer margin (conf/base.lua,
-- the one place gap numbers are invented). feh sizes its own window to the
-- image by default, which is why it used to spill past the screen on a large
-- wallpaper; the launch flags in services/Theme.qml do the actual fitting
-- (--geometry caps the window, --scale-down/--auto-zoom fit the image inside
-- it), this rule is the floor that keeps the window from exceeding the desk's
-- spacing even if a flag is ever dropped.
local feh_gaps = config.default_gaps.gaps_out
hl.window_rule({
  name = "feh",
  match = { initial_class = "feh" },
  float = true,
  content = "photo",
  center = true,
  rounding = 0,
  opacity = "1 override 1 override",
  size = {
    "monitor_w - " .. (feh_gaps.left + feh_gaps.right),
    "monitor_h - " .. (feh_gaps.top + feh_gaps.bottom),
  },
})

-- Spotify lives on the "music" shelf (declared drawer, hypr/lib/drawer.lua).

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

-- Focus-specific shadow: the global shadow is subtle, but it must only lift
-- the currently focused window. A dynamic rule keyed on the `focus` match
-- disables the shadow for everything else, so inactive sheets stay flat and
-- the active one reads as the one on top.
hl.window_rule({
  name = "focused-shadow",
  match = { focus = true },
  no_shadow = false,
})
hl.window_rule({
  name = "unfocused-no-shadow",
  match = { focus = false },
  no_shadow = true,
})

-- The scene layer's rules come last: `group` is decided by the scene that
-- names the class (hypr/scene/compile.lua), and a later rule is the one that
-- stands. Emitting here — rather than where the scenes are read — keeps every
-- window rule in the file that owns window rules.
require("hypr.scene.compile").emit(require("hypr.scene.spec").load())

-- Shelves last, so their workspace effect wins over any earlier class rule.
local drawer = require("hypr.lib.drawer")
drawer.rules(drawer.load())

-- A project's windows open because `,proj.sh open` was asked for a PROJECT,
-- not for each terminal in it. Four of them map in sequence, and every one
-- that takes focus as it maps drags the keyboard along behind the spawn
-- order, so the user lands on whichever window happened to be last rather
-- than on the tab they asked for. `,proj.sh` focuses the requested role once,
-- after the template has finished spawning; until then nothing in the group
-- should be pulling focus on its own.
hl.window_rule({
  name = "project-window-no-steal",
  match = { initial_class = "Proj-[A-Za-z0-9_-]+" },
  no_initial_focus = true,
})

-- Hidden holding places stay silent. A window parked on one of these special
-- workspaces is intentionally out of sight; it must not ask for focus or
-- respond to activation requests, and if the special workspace itself becomes
-- visible it is put away by the runtime callers that park windows here.
hl.window_rule({
  name = "hyprfocus-held-silence",
  match = { workspace = "special:hyprfocus-held" },
  no_focus = true,
  suppress_event = "activate activatefocus",
})
hl.window_rule({
  name = "deck-hold-silence",
  match = { workspace = "special:deck-hold" },
  no_focus = true,
  suppress_event = "activate activatefocus",
})

-- Nested Hyprland instances started by the e2e harness (tests/e2e/hq) open as
-- an `aquamarine` window. Keep them small, floating in a corner and out of
-- focus, so an agent's live test never takes over the desk.
hl.window_rule({
  name = "e2e-nested-hyprland",
  match = { class = "aquamarine" },
  float = true,
  size = { 640, 180 },
  move = { "monitor_w - 660", "monitor_h - 220" },
  no_initial_focus = true,
})
