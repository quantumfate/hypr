-- The machine-independent half of the desk: modal keys, the app registry,
-- and geometry profiles (keyed by output fingerprint, not host — see
-- hypr/lib/profile.lua). Every `config.<toplevel field>` read in hypr/* is
-- one of the tables this file, or a host file in conf/hosts/, builds.
--
-- Host files pick their deltas against this; what a host file must spell only
-- is what this file cannot know: its monitors, and any workspace engine
-- options it wants different from the spec defaults conf/host applies.

---The desk's geometry half, keyed by hypr.lib.profile's fingerprint of
---hl.get_monitors(), not by hostname. desk-dual's numbers are the former
---quantum-desktop ones, laptop-solo's the former quantum-laptop ones.
---@type table<string, { gaps_by_monitor?: table<string, table<string, any>> }>
local geometry_profiles = {
  [require("hypr.lib.profile").DESK_DUAL] = {
    -- Separation is a property of the panel, not of the config: 40px of
    -- outer gap is air on a 5120x1440 ultrawide and a wasted third of a
    -- laptop lid. The global in hypr/conf.lua is the ultrawide's; the
    -- secondary (a normal-aspect monitor) says so here. top stays 8: the
    -- bar reserves its own height, so a full 40px on top would stack two
    -- margins into a canyon (see hypr/events/solo_gaps.lua for the same rule).
    gaps_by_monitor = {
      secondary = { gaps_in = 6, gaps_out = 14 },
    },
  },
  [require("hypr.lib.profile").LAPTOP_SOLO] = {
    -- A lid has no room to give away.
    gaps_by_monitor = {
      primary = { gaps_in = 4, gaps_out = 8 },
      secondary = { gaps_in = 4, gaps_out = 8 },
    },
  },
}

return {
  main_mod = "SUPER",
  -- Passive peek cheatsheet: how long to dwell in a submap before it fades in.
  -- Short enough to feel like which-key rather than a delayed reaction.
  peek_delay_ms = 350,
  primary_mod = "CTRL",
  secondary_mod = "SHIFT",
  tertiary_mod = "ALT",
  ---@type table<string, AppScope>
  apps = {
    media_browser = { cmd = "zen-twilight -P Media --name zen-twilight-media", class = "zen-twilight-media" },
    -- The gaming scene's own zen instance (LEO-230): pinned to name:gaming by
    -- windowrules, opened and closed with the Dofus group by
    -- events/gaming.lua. It needs its OWN profile, not -P Media: zen is
    -- single-instance per profile, so launching a second -P Media window only
    -- opens a tab-strip window inside the running media browser's process —
    -- --name is ignored there, the class stays zen-twilight-media, and the
    -- +media-browser rule drags it to name:media. A distinct profile forces a
    -- distinct process, which is what makes --name (and therefore the class
    -- gate below) real.
    media_scene = { cmd = "zen-twilight -P GamingMedia --name zen-gaming-media", class = "zen-gaming-media" },
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
    mail = { cmd = "proton-mail", class = "Proton Mail" },
    calculator = { cmd = "qalculate-qt", class = "io.github.Qalculate.qalculate-qt" },
    app_launcher = { cmd = 'rofi -show drun -run-command "uwsm app -- {cmd}"', class = "" },
    bluetooth_manager = { cmd = "kitty --class Kitty-Bluetui bluetui", class = "Kitty-Bluetui" },
    package_manager_ui = { cmd = "shelly-ui", class = "com.shellyorg.shelly" },
    package_manager_tui = { cmd = "kitty --class Kitty-Parui parui", class = "Kitty-Parui" },
  },
  geometry_profiles = geometry_profiles,
}
