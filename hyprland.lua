local hypr_dir = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr"
package.path = package.path .. ";" .. hypr_dir .. "/?.lua"

---@class Config
---@field main_mod string
---@field peek_delay_ms integer
---@field primary_mod string
---@field secondary_mod string
---@field tertiary_mod string
---@field host_configs table<string, Hosts>
_G.config = {
  main_mod = "SUPER",
  -- Passive peek cheatsheet: how long to dwell in a submap before it fades in.
  -- Short enough to feel like which-key rather than a delayed reaction.
  peek_delay_ms = 350,
  primary_mod = "CTRL",
  secondary_mod = "SHIFT",
  tertiary_mod = "ALT",
  apps = {
    media_browser = { cmd = "zen-twilight -P Media --name zen-twilight-media", class = "zen-twilight-media" },
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
  host_configs = {
    ["quantum-laptop"] = {
      primary_monitor = "eDP-1",
      secondary_monitor = "HDMI-A-1",
      hyprlock_conf = os.getenv("HOME") .. "/.config/hypr/hyprlock-laptop.conf",
      -- A lid has no room to give away.
      gaps_by_monitor = {
        primary = { gaps_in = 4, gaps_out = 8 },
        secondary = { gaps_in = 4, gaps_out = 8 },
      },
      kb_options = "caps:swapescape",
      -- workspace_specs use monitor = "primary" as a sentinel, resolved to
      -- primary_monitor by the post-build pass at the bottom of this file.
      workspaces = {
        workspace_specs = {
          {
            workspace = "1",
            persistent = true,
            default = true,
            default_name = "code",
            layout = "monocle",
            monitor = "primary",
          },
          {
            workspace = "2",
            persistent = true,
            default_name = "creative",
            layout = "scrolling",
            monitor = "primary",
          },
          {
            workspace = "3",
            persistent = true,
            default_name = "proton",
            layout = "scrolling",
            monitor = "primary",
          },
          {
            workspace = "4",
            persistent = true,
            default_name = "media",
            layout = "scrolling",
            monitor = "primary",
          },
          {
            workspace = "5",
            persistent = true,
            gaps_in = 0,
            gaps_out = 0,
            border_size = 0,
            decorate = false,
            layout = "monocle",
            default_name = "gaming",
            monitor = "primary",
          },
          -- See the desktop host: same workspace, same reasoning.
          {
            workspace = "6",
            persistent = true,
            default_name = "logs",
            monitor = "primary",
            layout = "monocle",
          },
          {
            workspace = "special:comms",
            layout = "scrolling",
          },
          {
            workspace = "special:music",
            layout = "scrolling",
          },
          {
            workspace = "special:launcher",
            layout = "scrolling",
          },
          {
            workspace = "special:ankama",
            on_created_empty = "uwsm-app -- ,ankama-launcher.sh",
          },
        },
        workspace_keys = {
          "plus",
          "bracketleft",
          "braceleft",
          "parenleft",
          "ampersand",
          "equal",
          "parenright",
          "braceright",
          "bracketright",
          "asterisk",
        },
      },
    },
    ["quantum-desktop"] = {
      primary_monitor = "DP-1",
      secondary_monitor = "DP-2",
      hyprlock_conf = os.getenv("HOME") .. "/.config/hypr/hyprlock.conf",
      -- Separation is a property of the panel, not of the config: 40px of outer
      -- gap is air on a 5120x1440 ultrawide and a wasted third of a laptop lid.
      -- The global in conf.lua is the ultrawide's; everything else says so here.
      gaps_by_monitor = {
        secondary = { gaps_in = 6, gaps_out = 14 },
      },
      workspaces = {
        workspace_specs = {
          -- Hyprland drops layoutopt on workspace rules (only
          -- layoutopt:orientation is implemented), so layout_opts is consumed
          -- by hypr/events/layout_opts.lua, which rewrites the matching
          -- globals on workspace focus. Options may also be keyed by layout
          -- name to differ per layout on a workspace; see that file's header.
          -- Here: split ratio 1.25 on the widescreen primary, 1.0 on
          -- normal-aspect monitors.
          {
            workspace = "1",
            persistent = true,
            default = true,
            default_name = "code",
            monitor = "primary",
            -- Dwindle, with the terminals stacked into one group rather than
            -- spread across the panel (see windowrules.lua). That leaves two
            -- tiles however many project windows are open: the group on the
            -- left at roughly two thirds, the browser on the right at one, and
            -- the groupbar saying which terminal you are looking at.
            layout = "dwindle",
            layout_opts = {
              dwindle = { default_split_ratio = 2.0 },
              scrolling = { column_width = 0.67 },
            },
          },
          {
            workspace = "2",
            persistent = true,
            default_name = "creative",
            monitor = "primary",
            layout = "dwindle",
            layout_opts = {
              dwindle = { default_split_ratio = 1.0 },
            },
          },
          {
            workspace = "3",
            persistent = true,
            default_name = "proton",
            monitor = "primary",
            layout = "dwindle",
            layout_opts = {
              dwindle = { default_split_ratio = 1.0 },
            },
          },
          {
            workspace = "4",
            persistent = true,
            gaps_in = 0,
            gaps_out = 0,
            border_size = 0,
            decorate = false,
            default_name = "gaming",
            layout = "monocle",
            monitor = "primary",
          },
          {
            workspace = "5",
            persistent = true,
            default_name = "media",
            monitor = "secondary",
            layout = "dwindle",
            layout_opts = { default_split_ratio = 1.0 },
          },
          {
            workspace = "6",
            persistent = true,
            default_name = "logs",
            monitor = "secondary",
            layout = "monocle",
          },

          {
            workspace = "7",
            persistent = true,
            default_name = "misc",
            monitor = "secondary",
            layout = "dwindle",
            layout_opts = { default_split_ratio = 1.25, special_scale_factor = 1 },
          },
          {
            workspace = "special:comms",
            layout = "dwindle",
          },
          {
            workspace = "special:music",
            layout = "scrolling",
          },
          {
            workspace = "special:launcher",
            layout = "scrolling",
          },
          {
            workspace = "special:ankama",
            on_created_empty = "uwsm-app -- lutris lutris:rungameid/2",
          },
        },
        workspace_keys = {
          "plus",
          "bracketleft",
          "braceleft",
          "parenleft",
          "ampersand",
          "equal",
          "parenright",
          "braceright",
          "bracketright",
          "asterisk",
        },
      },
    },
  },
}

_G.config.__index = _G.config

-- Resolve the current host once, so every consumer reads `config.host.*`
-- without ever computing the hostname itself.
_G.config.host = assert(_G.config.host_configs[require("hypr.lib.util").hostname()], "no host_config for this hostname")

-- Resolve the "primary"/"secondary" monitor sentinels in workspace_specs to the
-- host's monitors. Done as a post-build pass since a Lua table constructor
-- cannot reference its own fields while being built.
local monitor_aliases = {
  primary = _G.config.host.primary_monitor,
  secondary = _G.config.host.secondary_monitor,
}
local gaps_by_monitor = _G.config.host.gaps_by_monitor or {}
for _, spec in ipairs(_G.config.host.workspaces.workspace_specs) do
  local role = spec.monitor
  if role == "primary" or role == "secondary" then
    spec.monitor = assert(
      monitor_aliases[role],
      "workspace " .. tostring(spec.workspace) .. " uses '" .. role .. "' but host has no such monitor"
    )
    -- Gaps the host declared for this monitor, unless the spec argued otherwise.
    -- The gaming workspace sets its own zeroes and keeps them.
    for key, value in pairs(gaps_by_monitor[role] or {}) do
      if spec[key] == nil then
        spec[key] = value
      end
    end
  end
end

require("hypr")
