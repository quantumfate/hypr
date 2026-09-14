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
  host_configs = {
    ["quantum-laptop"] = {
      primary_monitor = "eDP-1",
      secondary_monitor = "HDMI-A-1",
      hyprlock_conf = os.getenv("HOME") .. "/.config/hypr/hyprlock-laptop.conf",
      -- Gaps are geometry, resolved by output fingerprint below
      -- (geometry_profiles), not by which host this is.
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
            -- No hardcoded gaps (LEO-190): the profile fills them per monitor
            -- like any other workspace, and solo_gaps frames the lone Dofus
            -- group when nothing else is open (LEO-191). The old gaps_out = 0
            -- meant edge-to-edge clients; the group rule already makes this a
            -- single tile, so the workspace is shaped by the system, not by a
            -- "zero means special" sentinel.
            -- Engine-owned fields (see the workspaces.lua header): the scene's
            -- geometry decisions stay out of the workspace rule.
            engine = {
              -- Two-tile ratio declaration; see docs/scenes.md. A resize loop
              -- may correct drift internally; it is not this field.
              layout_opts = {
                dwindle = { default_split_ratio = 0.67 },
              },
              -- Opt out of solo framing (LEO-190/191): this scene is a fixed
              -- capture region, not a lone window that wants breathing room.
              -- With framing on, the gaps flipped between the base profile and
              -- the +180 widen every time the tile count changed (group alone
              -- vs group + scene browser), which moves the OBS crop under you.
              solo_gaps = "none",
            },
            -- No decoration overrides: the workspace takes the same default
            -- geometry as every other one, so the compositor groupbar makes
            -- its standard reservation (it insets the client and takes the
            -- top edge out of the window) and the group widget — which
            -- follows in the quickshell repo — paints on exactly that slot.
            -- With per-workspace exceptions the attached-bar geometry came
            -- apart: gaming floated the widget, code inset its tabs.
            -- The Dofus clients are one Hyprland group (windowrules.lua), so
            -- the workspace holds a single tile whatever the layout — dwindle
            -- rather than monocle so it can host other gaming windows (or, per
            -- LEO-232, integrate with streaming) without every one of them
            -- fighting monocle's window-swap-on-focus behavior. See
            -- windowrules.lua's Dofus/Ankama section for the group rule.
            layout = "dwindle",
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
      -- Gaps are geometry, resolved by output fingerprint below
      -- (geometry_profiles), not by which host this is.
      workspaces = {
        workspace_specs = {
          -- Hyprland drops layoutopt on workspace rules (only
          -- layoutopt:orientation is implemented), so engine.layout_opts is
          -- consumed by hypr/events/layout_opts.lua, which rewrites the
          -- matching globals on workspace focus. Options may also be keyed by
          -- layout name to differ per layout on a workspace; see that file's
          -- header. Anything under `engine` never reaches the workspace rule.
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
            -- left, the browser on the right, and the groupbar saying which
            -- terminal you are looking at. See docs/scenes.md.
            layout = "scene",
            engine = {
              -- Two-tile ratio declaration; see docs/scenes.md.
              layout_opts = {
                dwindle = { default_split_ratio = 0.67 },
                scrolling = { column_width = 0.67 },
              },
            },
          },
          {
            workspace = "2",
            persistent = true,
            default_name = "creative",
            monitor = "primary",
            layout = "dwindle",
            engine = {
              layout_opts = {
                dwindle = { default_split_ratio = 1.0 },
              },
            },
          },
          {
            workspace = "3",
            persistent = true,
            default_name = "proton",
            monitor = "primary",
            layout = "dwindle",
            engine = {
              layout_opts = {
                dwindle = { default_split_ratio = 1.0 },
              },
            },
          },
          {
            workspace = "4",
            persistent = true,
            -- No hardcoded gaps (LEO-190): the profile fills them per monitor
            -- like any other workspace, and solo_gaps frames the lone Dofus
            -- group when nothing else is open (LEO-191).
            -- Engine-owned fields (see the workspaces.lua header): the scene's
            -- geometry decisions stay out of the workspace rule.
            engine = {
              -- Two-tile ratio declaration; see docs/scenes.md. A resize loop
              -- may correct drift internally; it is not this field.
              layout_opts = {
                dwindle = { default_split_ratio = 0.67 },
              },
              -- Opt out of solo framing (LEO-190/191): this scene is a fixed
              -- capture region, not a lone window that wants breathing room.
              -- With framing on, the gaps flipped between the base profile and
              -- the +180 widen every time the tile count changed (group alone
              -- vs group + scene browser), which moves the OBS crop under you.
              solo_gaps = "none",
            },
            -- Dwindle, not monocle: the Dofus clients are one Hyprland group
            -- (windowrules.lua), so this holds a single tile either way — but
            -- dwindle leaves room to add other gaming windows and integrates
            -- with the planned streaming setup (LEO-232), unlike monocle.
            default_name = "gaming",
            layout = "dwindle",
            monitor = "primary",
          },
          {
            workspace = "5",
            persistent = true,
            default_name = "media",
            monitor = "secondary",
            layout = "dwindle",
            engine = {
              layout_opts = { default_split_ratio = 1.0 },
            },
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
            engine = {
              layout_opts = { default_split_ratio = 1.25, special_scale_factor = 1 },
            },
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
            -- Through the gate: focus mode refuses to START a game. An already
            -- running one is never touched (see ,focus-guard.sh).
            on_created_empty = "sh -c ',focus-guard.sh game && uwsm-app -- lutris lutris:rungameid/2'",
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
        -- Temporary host fork of the scene document until Lua consumes the
        -- $XDG_STATE_HOME scenes store. See docs/scenes.md.
        scenes = {
          {
            default_name = "gaming",
            blocks = {
              -- `collect`: a Dofus client dragged to another workspace mid-session
              -- comes back, because the group is the scene — a client left behind
              -- is one the roster and the OBS crop both stop seeing.
              { classes = { "Dofus.x64" }, group = true, order = 1, share = 0.67, collect = true },
              -- `deny`, not the default bar: this tile is a fixed region beside
              -- the group, and grouping it — even deliberately — would collapse
              -- the two-tile split the capture depends on.
              { classes = { "zen-gaming-media" }, order = 2, share = 0.33, guard = "deny" },
            },
            -- Classes that legitimately open here without belonging to a block.
            -- They are barred because `auto_group` grabs whatever opens while a
            -- group holds focus, and this workspace's main tile is a group.
            barred = { "steam_app_default", "steam_app_\\d+", "Ankama Launcher" },
            -- This scene's tile geometry is a fixed capture region, so a
            -- window that matches no block floats above it rather than taking
            -- a slot and shifting the split the crop is aimed at.
            strays = "float",
          },
          {
            default_name = "code",
            blocks = {
              -- No `collect`: a project terminal you moved to another workspace
              -- is where you wanted it. Only the gaming group is cohesive enough
              -- to be worth dragging home.
              { classes = { "Kitty-Main", "Proj-[A-Za-z0-9_-]+" }, group = true, order = 1, share = 0.67 },
              { classes = { "zen-twilight", "firefox-developer-edition" }, order = 2, share = 0.33 },
            },
          },
        },
      },
    },
  },
  -- Keyed by hypr.lib.profile's fingerprint of hl.get_monitors(), not by
  -- hostname: this is the geometry half of what used to live in host_configs
  -- (see LEO-220). desk-dual's numbers are the former quantum-desktop ones,
  -- laptop-solo's the former quantum-laptop ones — unchanged, just relocated.
  geometry_profiles = {
    [require("hypr.lib.profile").DESK_DUAL] = {
      -- Separation is a property of the panel, not of the config: 40px of
      -- outer gap is air on a 5120x1440 ultrawide and a wasted third of a
      -- laptop lid. The global in conf.lua is the ultrawide's; the secondary
      -- (a normal-aspect monitor) says so here. top stays 8: the bar reserves
      -- its own height, so a full 40px on top would stack two margins into a
      -- canyon (see hypr/events/solo_gaps.lua for the same rule).
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
  },
}

_G.config.__index = _G.config

-- Resolve the current host once, so every consumer reads `config.host.*`
-- without ever computing the hostname itself. This decides which workspaces
-- exist (host_configs is keyed by hostname on purpose: it encodes machines we
-- built by hand).
_G.config.host = assert(_G.config.host_configs[require("hypr.lib.util").hostname()], "no host_config for this hostname")

-- Geometry is decided separately, by output fingerprint rather than hostname
-- — see hypr/lib/profile.lua's header for why. `resolve()` honors a manual
-- SUPER Space w m override over the live fingerprint.
_G.config.profile = require("hypr.lib.profile").resolve()
require("hypr.lib.profile").publish(_G.config.profile)

-- Resolve the "primary"/"secondary" monitor sentinels in workspace_specs to
-- the host's monitors, and fill in the resolved profile's gaps. Done as a
-- post-build pass since a Lua table constructor cannot reference its own
-- fields while being built.
local monitor_aliases = {
  primary = _G.config.host.primary_monitor,
  secondary = _G.config.host.secondary_monitor,
}
local geometry = _G.config.geometry_profiles[_G.config.profile] or {}
require("hypr.lib.geometry").resolve(
  _G.config.host.workspaces.workspace_specs,
  monitor_aliases,
  geometry.gaps_by_monitor
)

require("hypr")
