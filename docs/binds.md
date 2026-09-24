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

## Root — always live

84 binds.

| Key                          | Does                                                     | Where it should live |
| ---------------------------- | -------------------------------------------------------- | -------------------- |
| `F1`                         | Dofus: activate team member 1                            |                      |
| `F2`                         | Dofus: activate team member 2                            |                      |
| `F23`                        | Dofus: next team member                                  |                      |
| `F3`                         | Dofus: activate team member 3                            |                      |
| `F4`                         | Dofus: activate team member 4                            |                      |
| `F5`                         | Dofus: activate team member 5                            |                      |
| `F6`                         | Dofus: activate team member 6                            |                      |
| `F7`                         | Dofus: activate team member 7                            |                      |
| `F8`                         | Dofus: activate team member 8                            |                      |
| `XF86AudioLowerVolume`       | Volume down                                              |                      |
| `XF86AudioMicMute`           | Mute microphone                                          |                      |
| `XF86AudioMute`              | Mute output                                              |                      |
| `XF86AudioNext`              | Media next track                                         |                      |
| `XF86AudioPause`             | Media play/pause                                         |                      |
| `XF86AudioPlay`              | Media play/pause                                         |                      |
| `XF86AudioPrev`              | Media previous track                                     |                      |
| `XF86AudioRaiseVolume`       | Volume up                                                |                      |
| `XF86MonBrightnessDown`      | Brightness down                                          |                      |
| `XF86MonBrightnessUp`        | Brightness up                                            |                      |
| `mouse:274`                  | Dofus: press current member (middle click)               |                      |
| `mouse:274`                  | Dofus: press current member (middle click) _(duplicate)_ |                      |
| `up`                         | Dofus: press current member                              |                      |
| `ALT+F10`                    | Dofus: start double-click                                |                      |
| `ALT+F11`                    | Dofus: stop double-click                                 |                      |
| `ALT+F23`                    | Dofus: previous team member                              |                      |
| `ALT+TAB`                    | Workspace: Next on this monitor                          |                      |
| `ALT+ampersand`              | Workspace & on this monitor                              |                      |
| `ALT+asterisk`               | Workspace \* on this monitor                             |                      |
| `ALT+b`                      | Open the Browser                                         |                      |
| `ALT+braceleft`              | Workspace { on this monitor                              |                      |
| `ALT+braceright`             | Workspace } on this monitor                              |                      |
| `ALT+bracketleft`            | Workspace [ on this monitor                              |                      |
| `ALT+bracketright`           | Workspace ] on this monitor                              |                      |
| `ALT+comma`                  | Control centre (theme, wallpaper, sound, focus)          |                      |
| `ALT+e`                      | Logs…                                                    |                      |
| `ALT+equal`                  | Workspace = on this monitor                              |                      |
| `ALT+f`                      | Modes…                                                   |                      |
| `ALT+h`                      | Focus the tile to the left                               |                      |
| `ALT+j`                      | Focus the next window in this tile                       |                      |
| `ALT+k`                      | Focus the previous window in this tile                   |                      |
| `ALT+l`                      | Focus the tile to the right                              |                      |
| `ALT+o`                      | Obsidian…                                                |                      |
| `ALT+parenleft`              | Workspace ( on this monitor                              |                      |
| `ALT+parenright`             | Workspace ) on this monitor                              |                      |
| `ALT+plus`                   | Workspace + on this monitor                              |                      |
| `ALT+r`                      | Open Application Launcher                                |                      |
| `ALT+return`                 | Open the Terminal                                        |                      |
| `ALT+semicolon`              | Close focused window (or its whole group)                |                      |
| `ALT+slash`                  | Show keybind cheatsheet                                  |                      |
| `ALT+space`                  | Which-key…                                               |                      |
| `ALT+t`                      | Open a project (picker)                                  |                      |
| `ALT+x`                      | Cycle the workspace layout                               |                      |
| `CTRL+ALT+e`                 | Open the power menu (wlogout)                            |                      |
| `CTRL+ALT+j`                 | Scroll this column to the next thing                     |                      |
| `CTRL+ALT+k`                 | Scroll this column to the previous thing                 |                      |
| `SHIFT+left`                 | Dofus: next team member                                  |                      |
| `SHIFT+right`                | Dofus: next team member                                  |                      |
| `SHIFT+ALT+TAB`              | Workspace: Previous on this monitor                      |                      |
| `SHIFT+ALT+ampersand`        | Move focused window to workspace & on this monitor       |                      |
| `SHIFT+ALT+asterisk`         | Move focused window to workspace \* on this monitor      |                      |
| `SHIFT+ALT+braceleft`        | Move focused window to workspace { on this monitor       |                      |
| `SHIFT+ALT+braceright`       | Move focused window to workspace } on this monitor       |                      |
| `SHIFT+ALT+bracketleft`      | Move focused window to workspace [ on this monitor       |                      |
| `SHIFT+ALT+bracketright`     | Move focused window to workspace ] on this monitor       |                      |
| `SHIFT+ALT+equal`            | Move focused window to workspace = on this monitor       |                      |
| `SHIFT+ALT+h`                | Swap this tile with the one to the left                  |                      |
| `SHIFT+ALT+j`                | Move this window forward in its group                    |                      |
| `SHIFT+ALT+k`                | Move this window back in its group                       |                      |
| `SHIFT+ALT+l`                | Swap this tile with the one to the right                 |                      |
| `SHIFT+ALT+parenleft`        | Move focused window to workspace ( on this monitor       |                      |
| `SHIFT+ALT+parenright`       | Move focused window to workspace ) on this monitor       |                      |
| `SHIFT+ALT+plus`             | Move focused window to workspace + on this monitor       |                      |
| `SHIFT+ALT+w`                | Pick a workspace                                         |                      |
| `SHIFT+CTRL+ALT+escape`      | Modes: return to neutral                                 |                      |
| `SHIFT+SUPER+TAB`            | Workspace: Previous on this monitor                      |                      |
| `SUPER+TAB`                  | Workspace: Next on this monitor                          |                      |
| `SUPER+XF86AudioLowerVolume` | Media player volume down                                 |                      |
| `SUPER+XF86AudioRaiseVolume` | Media player volume up                                   |                      |
| `SUPER+p`                    | Execute hyprpicker to extract hex code                   |                      |
| `SUPER+ALT+F`                | Fullscreen window                                        |                      |
| `SUPER+ALT+T`                | Toggle floating                                          |                      |
| `SUPER+ALT+X`                | Maximize window                                          |                      |
| `SUPER+ALT+m`                | Minimize Window                                          |                      |
| `SUPER+ALT+mouse:272`        | Move a window with left click                            |                      |

## `alttab` submap

6 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `escape`       | Cancel                                        |                      |
| `escape`       | Leave this submap, back one level             |                      |
| `return`       | Pick selected window                          |                      |
| `SHIFT+escape` | Cancel (reverse)                              |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap |                      |
| `SHIFT+return` | Pick selected window (reverse)                |                      |

## `applications` submap

10 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `b`            | Open the Browser                              |                      |
| `c`            | Open Calculator                               |                      |
| `d`            | Open Zen Browser media profile                |                      |
| `escape`       | Leave this submap, back one level             |                      |
| `f`            | Open Yazi                                     |                      |
| `m`            | Open Proton Pass                              |                      |
| `p`            | Open Shelly                                   |                      |
| `s`            | Open Shelly                                   |                      |
| `CTRL+d`       | Open the dev Browser                          |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap |                      |

## `configuration` submap

4 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `b`            | Open Bluetui                                  |                      |
| `escape`       | Leave this submap, back one level             |                      |
| `v`            | Open Wiremix                                  |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap |                      |

## `dofus` submap

13 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `a`            | Ankama launcher                               |                      |
| `c`            | Show focused window class                     |                      |
| `d`            | Toggle launch-on-open                         |                      |
| `escape`       | Leave this submap, back one level             |                      |
| `l`            | Assign character classes                      |                      |
| `n`            | Rename focused window                         |                      |
| `o`            | Show roster                                   |                      |
| `p`            | Copy settings to all accounts                 |                      |
| `r`            | Reload team store                             |                      |
| `s`            | Toggle swap                                   |                      |
| `t`            | Open team selector                            |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap |                      |
| `SHIFT+s`      | Selected team                                 |                      |

## `focus` submap

5 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `escape`       | Leave this submap, back one level             |                      |
| `f`            | Start work                                    |                      |
| `i`            | Focus mode status                             |                      |
| `s`            | Back to neutral                               |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap |                      |

## `layout` submap

3 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `escape`       | Leave this submap, back one level             |                      |
| `s`            | scrolling…                                    |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap |                      |

## `layout-scrolling` submap

7 binds.

| Key            | Does                                             | Where it should live |
| -------------- | ------------------------------------------------ | -------------------- |
| `equal`        | Scrolling: widen the active column               |                      |
| `escape`       | Leave this submap, back one level                |                      |
| `f`            | Scrolling: fit the active column to the viewport |                      |
| `h`            | Scrolling: move window to the previous column    |                      |
| `l`            | Scrolling: move window to the next column        |                      |
| `minus`        | Scrolling: narrow the active column              |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap    |                      |

## `logs` submap

13 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `a`            | Audit / denials                               |                      |
| `b`            | This boot, from the top                       |                      |
| `e`            | Errors this boot                              |                      |
| `escape`       | Leave this submap, back one level             |                      |
| `f`            | Live journal                                  |                      |
| `g`            | Go to the logs workspace                      |                      |
| `h`            | hyprfocus decisions                           |                      |
| `k`            | Kernel ring buffer                            |                      |
| `l`            | Pick a log source                             |                      |
| `p`            | Previous boot                                 |                      |
| `w`            | Warnings this boot                            |                      |
| `x`            | Close all log sessions                        |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap |                      |

## `modes` submap

5 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `escape`       | Leave this submap, back one level             |                      |
| `g`            | Enter Gaming                                  |                      |
| `s`            | Enter Study                                   |                      |
| `w`            | Enter Work                                    |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap |                      |

## `obsidian` submap

5 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `escape`       | Leave this submap, back one level             |                      |
| `n`            | New note                                      |                      |
| `s`            | Vault status                                  |                      |
| `t`            | Tag tree                                      |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap |                      |

## `pokemon` submap

4 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `escape`       | Leave this submap, back one level             |                      |
| `l`            | Open the left Pokemon media window            |                      |
| `r`            | Open the right Pokemon media window           |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap |                      |

## `project` submap

9 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `escape`       | Leave this submap, back one level             |                      |
| `n`            | Focus the active project's nvim window        |                      |
| `o`            | Open a project scope (picker)                 |                      |
| `p`            | Open a project (its default window)           |                      |
| `r`            | Focus the active project's run window         |                      |
| `y`            | Focus the active project's yazi window        |                      |
| `z`            | Focus the active project's zsh window         |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap |                      |
| `SHIFT+k`      | Kill the focused project (all its windows)    |                      |

## `screen-record` submap

4 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `escape`       | Leave this submap, back one level             |                      |
| `o`            | Record current output (again to stop)         |                      |
| `r`            | Record a region (again to stop)               |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap |                      |

## `screen-shot` submap

5 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `escape`       | Leave this submap, back one level             |                      |
| `o`            | Screenshot current output                     |                      |
| `r`            | Screenshot a selected region                  |                      |
| `w`            | Screenshot current window                     |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap |                      |

## `screencapture` submap

4 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `escape`       | Leave this submap, back one level             |                      |
| `r`            | Screen record…                                |                      |
| `s`            | Screenshot…                                   |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap |                      |

## `shelf` submap

10 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `a`            | Ankama Launcher                               |                      |
| `c`            | CopyQ                                         |                      |
| `escape`       | Leave this submap, back one level             |                      |
| `k`            | ckb-next                                      |                      |
| `l`            | Lutris                                        |                      |
| `m`            | Spotify                                       |                      |
| `s`            | Signal                                        |                      |
| `t`            | Steam                                         |                      |
| `v`            | Vesktop                                       |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap |                      |

## `shell` submap

14 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `b`            | Toggle notifications                          |                      |
| `c`            | Open the Control Centre                       |                      |
| `d`            | Toggle do-not-disturb                         |                      |
| `escape`       | Leave this submap, back one level             |                      |
| `f`            | Focus mode…                                   |                      |
| `h`            | IPC help                                      |                      |
| `i`            | Theme info                                    |                      |
| `m`            | Toggle system monitor                         |                      |
| `n`            | Next wallpaper                                |                      |
| `p`            | Previous wallpaper                            |                      |
| `t`            | Cycle theme                                   |                      |
| `u`            | Open the System Center                        |                      |
| `x`            | Diagnose window placement                     |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap |                      |

## `terminal` submap

5 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `escape`       | Leave this submap, back one level             |                      |
| `return`       | Open the Terminal                             |                      |
| `s`            | Open a project on its shell window            |                      |
| `ALT+f`        | Open the floating Terminal                    |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap |                      |

## `which` submap

14 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `a`            | Applications                                  |                      |
| `c`            | Configuration                                 |                      |
| `d`            | Dofus                                         |                      |
| `escape`       | Leave this submap, back one level             |                      |
| `k`            | Toggle keyboard layout                        |                      |
| `m`            | Layout                                        |                      |
| `n`            | Pokemon                                       |                      |
| `p`            | Projects                                      |                      |
| `q`            | Shell / Quickshell                            |                      |
| `r`            | Window management                             |                      |
| `s`            | Screen capture                                |                      |
| `t`            | Terminal                                      |                      |
| `w`            | Shelves                                       |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap |                      |

## `window-management` submap

11 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `e`            | Cycle the workspace layout                    |                      |
| `escape`       | Leave this submap, back one level             |                      |
| `h`            | Resize vertically by -10                      |                      |
| `j`            | Resize horizontally by -10                    |                      |
| `k`            | Resize horizontally by 10                     |                      |
| `l`            | Resize vertically by 10                       |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap |                      |
| `SUPER+h`      | Resize vertically by -20                      |                      |
| `SUPER+j`      | Resize horizontally by -20                    |                      |
| `SUPER+k`      | Resize horizontally by 20                     |                      |
| `SUPER+l`      | Resize vertically by 20                       |                      |
