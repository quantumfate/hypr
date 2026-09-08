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
  peek_delay_ms = 2000,
  primary_mod = "CTRL",
  secondary_mod = "SHIFT",
  tertiary_mod = "ALT",
  apps = {
    media_browser = { cmd = "zen-twilight -P Media --name zen-twilight-media", class = "zen-twilight-media" },
    main_browser = { cmd = "zen-twilight", class = "zen-twilight" },
    dev_browser = { cmd = "firefox-developer-edition", class = "firefox-developer-edition" },
    terminal = { cmd = "kitty --class Kitty-Main", class = "Kitty-Main" },
    terminal_float = { cmd = "kitty --class Kitty-Float", class = "Kitty-Float" },
    tmux = { cmd = "kitty --class Tmux-Main tms", class = "Tmux-Main" },
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
            on_created_empty = "gamemoderun ankama-launcher",
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
      workspaces = {
        workspace_specs = {
          -- layout_opts overrides the global dwindle default_split_ratio
          -- (see hypr/layouts/dwindle.lua) per workspace: 1.25 on the
          -- widescreen primary, 1.0 on normal-aspect monitors.
          {
            workspace = "1",
            persistent = true,
            default = true,
            default_name = "code",
            monitor = "primary",
            layout = "dwindle",
            layout_opts = { default_split_ratio = 1.25 },
          },
          {
            workspace = "2",
            persistent = true,
            default_name = "creative",
            monitor = "primary",
            layout = "dwindle",
            layout_opts = { default_split_ratio = 1.0 },
          },
          {
            workspace = "3",
            persistent = true,
            default_name = "proton",
            monitor = "primary",
            layout = "dwindle",
            layout_opts = { default_split_ratio = 1.0 },
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
            on_created_empty = "gamemoderun ankama-launcher",
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
for _, spec in ipairs(_G.config.host.workspaces.workspace_specs) do
  if spec.monitor == "primary" or spec.monitor == "secondary" then
    spec.monitor = assert(
      monitor_aliases[spec.monitor],
      "workspace " .. tostring(spec.workspace) .. " uses '" .. spec.monitor .. "' but host has no such monitor"
    )
  end
end

require("hypr")
