-- The machine-independent half of the desk: modal keys, the app registry,
-- and geometry profiles (keyed by output fingerprint, not host — see
-- hypr/lib/profile.lua). Every `config.<toplevel field>` read in hypr/* is
-- one of the tables this file, or a host file in conf/hosts/, builds.
--
-- Host files pick their deltas against this; what a host file must spell only
-- is what this file cannot know: its monitors, and any workspace engine
-- options it wants different from the spec defaults conf/host applies.

-- The one place gap numbers are invented (AGENTS.md: nothing else does).
-- `hypr/conf.lua`'s `general` block and `conf/host.lua`'s pre-load fallback
-- both read this rather than carrying their own literal, so widening a gap
-- here is the whole change.
--
-- top stays deliberately tighter than the other three sides: the bar is a
-- WlrLayershell top-layer surface with no explicit `exclusiveZone`, so
-- Quickshell's PanelWindow reserves its own height (`Theme.barReserved`,
-- ~46px) from the compositor's work area automatically -- that reservation
-- already lands in the `ctx.area` the scene layout is handed. A full outer
-- gap on top of that stacks two margins into a canyon (the bug this profile
-- used to have: top and the sides shared one number). This default is what a
-- monitor with no `gaps_by_monitor` entry -- and the compositor's own boot-time
-- gaps, before any host resolves -- gets.
---@type { gaps_in: number, gaps_out: { top: number, right: number, bottom: number, left: number } }
local default_gaps = { gaps_in = 24, gaps_out = { top = 12, right = 0, bottom = 56, left = 56 } }

---The desk's geometry half, keyed by hypr.lib.profile's fingerprint of
---hl.get_monitors(), not by hostname. desk-dual's numbers are the former
---quantum-desktop ones, laptop-solo's the former quantum-laptop ones.
---
---LEO note: these used to be dead for the scene layout (only the bar's side
---inset ever read them) -- `hypr/scene/provider.lua` fed the compositor's
---*global* `general:gaps_in`/`general:gaps_out` into every scene regardless
---of workspace, so a monitor's own entry here never reached a tiled window.
---The provider now looks a workspace's own spec up by `default_name` first
---(`hypr/lib/geometry.lua`'s `M.resolve` already filled these onto
---`workspace_specs` at load time), so per-monitor gaps finally apply.
---
---Numbers are roughly 5x the pre-fix live values (gaps_in 12, gaps_out top 8 /
---sides+bottom 40) per the user's ask, scaled by panel size. The desk-dual
---pair is deliberately asymmetric: the 5120x1440 ultrawide (primary) takes a
---tight left and a flush right, the normal-aspect secondary 64 on both sides.
---top is 12 wherever the bar shows (every output except a laptop's external
---secondary, which quickshell/modules/bar/Bar.qml excludes from the bar the
---same way it excludes the desktop's case panel) -- see the module comment
---above for why top stays small rather than doubling the bar's own
---reservation.
---@type table<string, { gaps_by_monitor?: table<string, table<string, any>> }>
local geometry_profiles = {
  [require("hypr.lib.profile").DESK_DUAL] = {
    gaps_by_monitor = {
      primary = { gaps_in = 20, gaps_out = { top = 12, right = 0, bottom = 15, left = 30 } },
      secondary = { gaps_in = 48, gaps_out = { top = 12, right = 64, bottom = 64, left = 64 } },
    },
  },
  [require("hypr.lib.profile").LAPTOP_SOLO] = {
    gaps_by_monitor = {
      primary = { gaps_in = 40, gaps_out = { top = 12, right = 48, bottom = 48, left = 48 } },
      -- The laptop's secondary (external monitor, HDMI-A-1) never carries a
      -- bar (Bar.qml's excludedScreens), so nothing reserves height there --
      -- top can match the other three sides.
      secondary = { gaps_in = 40, gaps_out = { top = 48, right = 48, bottom = 48, left = 48 } },
    },
  },
}

return {
  main_mod = "SUPER",
  primary_mod = "CTRL",
  secondary_mod = "SHIFT",
  tertiary_mod = "ALT",
  -- Shelves (docs/shelves.md) are declared drawers now (LEO-363): key, class,
  -- launch command and scene assignment all live in the hyprfocus declaration
  -- (`base.drawers`, `scenes.<name>.drawers`), read at runtime by
  -- `hypr/lib/drawer.lua`. Nothing host-specific remains here — window
  -- geometry (float, centered, 60% x 70%) is engine policy in that module,
  -- not per-drawer data.
  ---@type table<string, AppScope>
  apps = {
    media_browser = { cmd = "zen-twilight -P Media --name zen-twilight-media", class = "zen-twilight-media" },
    -- The gaming scene's own zen instance (LEO-230): pinned to name:gaming by
    -- windowrules, opened and closed with the Dofus group by the scene's
    -- declared companion (hypr/scene/companion.lua; the spawn lives in the
    -- scene document now, so this entry names the same command for the binds
    -- that still spawn it directly). It needs its OWN profile, not -P Media:
    -- zen is single-instance per profile, so launching a second -P Media
    -- window only opens a tab-strip window inside the running media browser's
    -- process — --name is ignored there, the class stays zen-twilight-media,
    -- and the +media-browser rule drags it to name:media. A distinct profile
    -- forces a distinct process, which is what makes --name (and therefore
    -- the class gate below) real.
    scene_browser = { cmd = "zen-twilight -P GamingMedia --name zen-gaming-media", class = "zen-gaming-media" },
    main_browser = { cmd = "zen-twilight", class = "zen-twilight" },
    dev_browser = { cmd = "firefox-developer-edition", class = "firefox-developer-edition" },
    terminal = { cmd = "kitty --class Kitty-Main", class = "Kitty-Main" },
    terminal_float = { cmd = "kitty --class Kitty-Float", class = "Kitty-Float" },
    -- Project sessions — the only tmux entry point. `,proj.sh` spawns the kitty
    -- itself (and its own uwsm scope), so binds must call it directly, never
    -- via bind.app_entry. Each window is classed `Proj-<project>`, so the class
    -- here is a pattern: it matches any project window, and a single project is
    -- addressable on its own when a rule needs that.
    project = { cmd = ",proj.sh pick", class = "Proj-[A-Za-z0-9_-]+" },
    volume_control = { cmd = "kitty --class Kitty-Wiremix wiremix", class = "Kitty-Wiremix" },
    file_manager = { cmd = "kitty --class Kitty-Yazi yazi", class = "Kitty-Yazi" },
    password_manager = { cmd = "proton-pass", class = "Proton Pass" },
    -- Live class is "proton-mail" (verified via hyprctl clients), not the
    -- capitalized display name; the stale "Proton Mail" here never matched
    -- the real window, so the +proton static route (hypr/windowrules.lua)
    -- silently never fired and the window opened wherever it was focused
    -- (LEO-382 part 3).
    mail = { cmd = "proton-mail", class = "proton-mail" },
    calculator = { cmd = "qalculate-qt", class = "io.github.Qalculate.qalculate-qt" },
    app_launcher = { cmd = 'rofi -show drun -run-command "uwsm app -- {cmd}"', class = "" },
    bluetooth_manager = { cmd = "kitty --class Kitty-Bluetui bluetui", class = "Kitty-Bluetui" },
    package_manager_ui = { cmd = "shelly-ui", class = "com.shellyorg.shelly" },
    package_manager_tui = { cmd = "kitty --class Kitty-Parui parui", class = "Kitty-Parui" },
  },
  geometry_profiles = geometry_profiles,
  default_gaps = default_gaps,
}
