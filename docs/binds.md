# Every bind, and where it belongs

The inventory of what this desk binds right now, and the working document
for deciding where each one should live. The architecture it answers to is
[system-config/docs/bindings.md](../../system-config/docs/bindings.md) —
system-level, contextual, mode-scoped — and the scene contract in
[docs/scenes.md](scenes.md); this file is the census, not the theory.

Generated from the **live** registry (`hyprctl binds` joined with
`$QF_STORE/whichkey.json`), so it lists what actually fires, not what the
source hopes it does. Regenerate after any bind change:

```sh
just binds-doc
```

### Where `mod+h`/`mod+l` think you are

The seat these two keys step out of is read off the **active window** — its
own monitor and workspace — never `hl.get_active_monitor()` /
`hl.get_active_workspace()`. Measured on this desk: with the keyboard in a
window on DP-2, both of those still answered DP-1 and DP-1's workspace, so the
keys walked the other monitor's tile list and, at that monitor's outer edge,
found no adjacent monitor and did nothing — "mod+l cannot leave the left
monitor" (2026-09-25).

When nothing holds the keyboard at all — the seat just crossed onto a monitor
whose workspace is empty, and `misc.no_focus_fallback` leaves the keyboard
nowhere — there is nothing left to ask: the compositor's focused-monitor mark
does not move onto an empty output, and neither `focus({monitor})` nor a
workspace focus warps the cursor. So the crossing remembers where it went
(`crossed_to` in `hypr/binds.lua`), and the opposite key reads it back. That
memory is dropped the moment any window holds focus again — a live window is
always the truth.

## Root — always live

83 binds.

| Key                        | Does                                                | Where it should live |
| -------------------------- | --------------------------------------------------- | -------------------- |
| `F1`                       | Dofus: activate team member 1                       | contextual           |
| `F2`                       | Dofus: activate team member 2                       | contextual           |
| `F23`                      | Dofus: next team member                             | contextual           |
| `F3`                       | Dofus: activate team member 3                       | contextual           |
| `F4`                       | Dofus: activate team member 4                       | contextual           |
| `F5`                       | Dofus: activate team member 5                       | contextual           |
| `F6`                       | Dofus: activate team member 6                       | contextual           |
| `F7`                       | Dofus: activate team member 7                       | contextual           |
| `F8`                       | Dofus: activate team member 8                       | contextual           |
| `XF86AudioLowerVolume`     | Volume down                                         | system               |
| `XF86AudioMicMute`         | Mute microphone                                     | system               |
| `XF86AudioMute`            | Mute output                                         | system               |
| `XF86AudioNext`            | Media next track                                    | system               |
| `XF86AudioPause`           | Media play/pause                                    | system               |
| `XF86AudioPlay`            | Media play/pause                                    | system               |
| `XF86AudioPrev`            | Media previous track                                | system               |
| `XF86AudioRaiseVolume`     | Volume up                                           | system               |
| `XF86MonBrightnessDown`    | Brightness down                                     | system               |
| `XF86MonBrightnessUp`      | Brightness up                                       | system               |
| `mouse:274`                | Dofus: press current member (middle click)          | contextual           |
| `up`                       | Dofus: press current member                         | contextual           |
| `ALT+TAB`                  | Alt-tab: next window                                | system               |
| `ALT+XF86AudioLowerVolume` | Media player volume down                            | system               |
| `ALT+XF86AudioRaiseVolume` | Media player volume up                              | system               |
| `ALT+p`                    | Execute hyprpicker to extract hex code              | system               |
| `ALT+SUPER+F`              | Fullscreen window                                   | system               |
| `ALT+SUPER+T`              | Toggle floating                                     | system               |
| `ALT+SUPER+X`              | Maximize window                                     | system               |
| `ALT+SUPER+m`              | Minimize Window                                     | system               |
| `ALT+SUPER+mouse:272`      | Move a window with left click                       | system               |
| `CTRL+SUPER+e`             | Open the power menu (wlogout)                       | system               |
| `CTRL+SUPER+j`             | Scroll this column to the next thing                | system               |
| `CTRL+SUPER+k`             | Scroll this column to the previous thing            | system               |
| `SHIFT+left`               | Dofus: previous team member                         | contextual           |
| `SHIFT+right`              | Dofus: next team member                             | contextual           |
| `SHIFT+ALT+TAB`            | Alt-tab: previous window                            | system               |
| `SHIFT+CTRL+SUPER+escape`  | Modes: return to neutral                            | system               |
| `SHIFT+SUPER+TAB`          | Workspace: Previous on this monitor                 | system               |
| `SHIFT+SUPER+ampersand`    | Move focused window to workspace & on this monitor  | system               |
| `SHIFT+SUPER+asterisk`     | Move focused window to workspace \* on this monitor | system               |
| `SHIFT+SUPER+braceleft`    | Move focused window to workspace { on this monitor  | system               |
| `SHIFT+SUPER+braceright`   | Move focused window to workspace } on this monitor  | system               |
| `SHIFT+SUPER+bracketleft`  | Move focused window to workspace [ on this monitor  | system               |
| `SHIFT+SUPER+bracketright` | Move focused window to workspace ] on this monitor  | system               |
| `SHIFT+SUPER+equal`        | Move focused window to workspace = on this monitor  | system               |
| `SHIFT+SUPER+h`            | Swap this tile with the one to the left             | system               |
| `SHIFT+SUPER+j`            | Move this window forward in its group               | system               |
| `SHIFT+SUPER+k`            | Move this window back in its group                  | system               |
| `SHIFT+SUPER+l`            | Swap this tile with the one to the right            | system               |
| `SHIFT+SUPER+parenleft`    | Move focused window to workspace ( on this monitor  | system               |
| `SHIFT+SUPER+parenright`   | Move focused window to workspace ) on this monitor  | system               |
| `SHIFT+SUPER+plus`         | Move focused window to workspace + on this monitor  | system               |
| `SHIFT+SUPER+w`            | Pick a workspace                                    | system               |
| `SUPER+F10`                | Dofus: start double-click                           | contextual           |
| `SUPER+F11`                | Dofus: stop double-click                            | contextual           |
| `SUPER+F23`                | Dofus: previous team member                         | contextual           |
| `SUPER+TAB`                | Workspace: Next on this monitor                     | system               |
| `SUPER+ampersand`          | Workspace & on this monitor                         | system               |
| `SUPER+asterisk`           | Workspace \* on this monitor                        | system               |
| `SUPER+b`                  | Open the Browser                                    | system               |
| `SUPER+braceleft`          | Workspace { on this monitor                         | system               |
| `SUPER+braceright`         | Workspace } on this monitor                         | system               |
| `SUPER+bracketleft`        | Workspace [ on this monitor                         | system               |
| `SUPER+bracketright`       | Workspace ] on this monitor                         | system               |
| `SUPER+comma`              | Control centre (theme, wallpaper, sound, focus)     | system               |
| `SUPER+e`                  | Logs…                                               | tree: logs           |
| `SUPER+equal`              | Workspace = on this monitor                         | system               |
| `SUPER+f`                  | Modes…                                              | tree: modes          |
| `SUPER+h`                  | Focus the tile to the left                          | system               |
| `SUPER+j`                  | Focus the next window in this tile                  | system               |
| `SUPER+k`                  | Focus the previous window in this tile              | system               |
| `SUPER+l`                  | Focus the tile to the right                         | system               |
| `SUPER+o`                  | Obsidian…                                           | tree: obsidian       |
| `SUPER+parenleft`          | Workspace ( on this monitor                         | system               |
| `SUPER+parenright`         | Workspace ) on this monitor                         | system               |
| `SUPER+plus`               | Workspace + on this monitor                         | system               |
| `SUPER+r`                  | Open Application Launcher                           | system               |
| `SUPER+return`             | Open the Terminal                                   | system               |
| `SUPER+semicolon`          | Close focused window (or its whole group)           | system               |
| `SUPER+slash`              | Show keybind cheatsheet                             | system               |
| `SUPER+space`              | Which-key…                                          | system               |
| `SUPER+t`                  | Open a project (picker)                             | system               |
| `SUPER+x`                  | Cycle the workspace layout                          | system               |

## `alttab` submap

6 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `escape`       | Cancel                                        | system               |
| `escape`       | Leave this submap, back one level             | system               |
| `return`       | Pick selected window                          |                      |
| `SHIFT+escape` | Cancel (reverse)                              | system               |
| `SHIFT+escape` | Leave the whole tree, back to the base submap | system               |
| `SHIFT+return` | Pick selected window (reverse)                |                      |

## `applications` submap

10 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `b`            | Open the Browser                              |                      |
| `c`            | Open Calculator                               |                      |
| `d`            | Open Zen Browser media profile                |                      |
| `escape`       | Leave this submap, back one level             | system               |
| `f`            | Open Yazi                                     |                      |
| `m`            | Open Proton Pass                              |                      |
| `p`            | Open Shelly                                   |                      |
| `s`            | Open Shelly                                   |                      |
| `CTRL+d`       | Open the dev Browser                          |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap | system               |

## `configuration` submap

4 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `b`            | Open Bluetui                                  |                      |
| `escape`       | Leave this submap, back one level             | system               |
| `v`            | Open Wiremix                                  |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap | system               |

## `dofus` submap

13 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `a`            | Ankama launcher                               | scene: dofus         |
| `c`            | Show focused window class                     | scene: dofus         |
| `d`            | Toggle launch-on-open                         | scene: dofus         |
| `escape`       | Leave this submap, back one level             | system               |
| `l`            | Assign character classes                      | scene: dofus         |
| `n`            | Rename focused window                         | scene: dofus         |
| `o`            | Show roster                                   | scene: dofus         |
| `p`            | Copy settings to all accounts                 | scene: dofus         |
| `r`            | Reload team store                             | scene: dofus         |
| `s`            | Toggle swap                                   | scene: dofus         |
| `t`            | Open team selector                            | scene: dofus         |
| `SHIFT+escape` | Leave the whole tree, back to the base submap | system               |
| `SHIFT+s`      | Selected team                                 | scene: dofus         |

## `focus` submap

5 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `escape`       | Leave this submap, back one level             | system               |
| `f`            | Start work                                    |                      |
| `i`            | Focus mode status                             |                      |
| `s`            | Back to neutral                               |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap | system               |

## `layout` submap

3 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `escape`       | Leave this submap, back one level             | system               |
| `s`            | scrolling…                                    |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap | system               |

## `layout-scrolling` submap

7 binds.

| Key            | Does                                             | Where it should live |
| -------------- | ------------------------------------------------ | -------------------- |
| `equal`        | Scrolling: widen the active column               |                      |
| `escape`       | Leave this submap, back one level                | system               |
| `f`            | Scrolling: fit the active column to the viewport |                      |
| `h`            | Scrolling: move window to the previous column    |                      |
| `l`            | Scrolling: move window to the next column        |                      |
| `minus`        | Scrolling: narrow the active column              |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap    | system               |

## `logs` submap

13 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `a`            | Audit / denials                               |                      |
| `b`            | This boot, from the top                       |                      |
| `e`            | Errors this boot                              |                      |
| `escape`       | Leave this submap, back one level             | system               |
| `f`            | Live journal                                  |                      |
| `g`            | Go to the logs workspace                      |                      |
| `h`            | hyprfocus decisions                           |                      |
| `k`            | Kernel ring buffer                            |                      |
| `l`            | Pick a log source                             |                      |
| `p`            | Previous boot                                 |                      |
| `w`            | Warnings this boot                            |                      |
| `x`            | Close all log sessions                        |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap | system               |

## `modes` submap

5 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `escape`       | Leave this submap, back one level             | system               |
| `g`            | Enter Gaming                                  |                      |
| `s`            | Enter Study                                   |                      |
| `w`            | Enter Work                                    |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap | system               |

## `obsidian` submap

5 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `escape`       | Leave this submap, back one level             | system               |
| `n`            | New note                                      |                      |
| `s`            | Vault status                                  |                      |
| `t`            | Tag tree                                      |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap | system               |

## `pokemon` submap

4 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `escape`       | Leave this submap, back one level             | system               |
| `l`            | Open the left Pokemon media window            |                      |
| `r`            | Open the right Pokemon media window           |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap | system               |

## `project` submap

9 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `escape`       | Leave this submap, back one level             | system               |
| `n`            | Focus the active project's nvim window        |                      |
| `o`            | Open a project scope (picker)                 |                      |
| `p`            | Open a project (its default window)           |                      |
| `r`            | Focus the active project's run window         |                      |
| `y`            | Focus the active project's yazi window        |                      |
| `z`            | Focus the active project's zsh window         |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap | system               |
| `SHIFT+k`      | Kill the focused project (all its windows)    |                      |

## `screen-record` submap

4 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `escape`       | Leave this submap, back one level             | system               |
| `o`            | Record current output (again to stop)         |                      |
| `r`            | Record a region (again to stop)               |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap | system               |

## `screen-shot` submap

5 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `escape`       | Leave this submap, back one level             | system               |
| `o`            | Screenshot current output                     |                      |
| `r`            | Screenshot a selected region                  |                      |
| `w`            | Screenshot current window                     |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap | system               |

## `screencapture` submap

4 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `escape`       | Leave this submap, back one level             | system               |
| `r`            | Screen record…                                |                      |
| `s`            | Screenshot…                                   |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap | system               |

## `shelf` submap

10 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `a`            | Ankama Launcher                               |                      |
| `c`            | CopyQ                                         |                      |
| `escape`       | Leave this submap, back one level             | system               |
| `k`            | ckb-next                                      |                      |
| `l`            | Lutris                                        |                      |
| `m`            | Spotify                                       |                      |
| `s`            | Signal                                        |                      |
| `t`            | Steam                                         |                      |
| `v`            | Vesktop                                       |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap | system               |

## `shell` submap

14 binds.

| Key            | Does                                          | Where it should live                         |
| -------------- | --------------------------------------------- | -------------------------------------------- |
| `b`            | Toggle notifications                          | tree: shell                                  |
| `c`            | Open the Control Centre                       | tree: shell                                  |
| `d`            | Toggle do-not-disturb                         | tree: shell                                  |
| `escape`       | Leave this submap, back one level             | system                                       |
| `f`            | Focus mode…                                   | tree: focus (door)                           |
| `h`            | IPC help                                      | tree: shell                                  |
| `i`            | Theme info                                    | tree: theme                                  |
| `m`            | Toggle system monitor                         | tree: shell                                  |
| `n`            | Next wallpaper                                | tree: theme                                  |
| `p`            | Previous wallpaper                            | tree: theme                                  |
| `t`            | Cycle theme                                   | tree: theme                                  |
| `u`            | Open the System Center                        | tree: shell                                  |
| `x`            | Diagnose window placement                     | dev-only — does not belong beside daily keys |
| `SHIFT+escape` | Leave the whole tree, back to the base submap | system                                       |

## `terminal` submap

5 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `escape`       | Leave this submap, back one level             | system               |
| `return`       | Open the Terminal                             |                      |
| `s`            | Open a project on its shell window            |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap | system               |
| `SUPER+f`      | Open the floating Terminal                    |                      |

## `which` submap

14 binds.

| Key            | Does                                          | Where it should live           |
| -------------- | --------------------------------------------- | ------------------------------ |
| `a`            | Applications                                  | tree: applications (door)      |
| `c`            | Configuration                                 | tree: configuration (door)     |
| `d`            | Dofus                                         | contextual                     |
| `escape`       | Leave this submap, back one level             | system                         |
| `k`            | Toggle keyboard layout                        |                                |
| `m`            | Layout                                        | tree: layout (door)            |
| `n`            | Pokemon                                       | tree: pokemon (door)           |
| `p`            | Projects                                      | tree: project (door)           |
| `q`            | Shell / Quickshell                            | tree: shell (door)             |
| `r`            | Window management                             | tree: window-management (door) |
| `s`            | Screen capture                                | tree: screencapture (door)     |
| `t`            | Terminal                                      | tree: terminal (door)          |
| `w`            | Shelves                                       | tree: shelf (door)             |
| `SHIFT+escape` | Leave the whole tree, back to the base submap | system                         |

## `window-management` submap

10 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `escape`       | Leave this submap, back one level             | system               |
| `h`            | Resize vertically by -10                      | system               |
| `j`            | Resize horizontally by -10                    | system               |
| `k`            | Resize horizontally by 10                     | system               |
| `l`            | Resize vertically by 10                       | system               |
| `ALT+h`        | Resize vertically by -20                      | system               |
| `ALT+j`        | Resize horizontally by -20                    | system               |
| `ALT+k`        | Resize horizontally by 20                     | system               |
| `ALT+l`        | Resize vertically by 20                       | system               |
| `SHIFT+escape` | Leave the whole tree, back to the base submap | system               |
