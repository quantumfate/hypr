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
| `ALT+TAB`                  | Alt-tab: next window                                |                      |
| `ALT+XF86AudioLowerVolume` | Media player volume down                            | system               |
| `ALT+XF86AudioRaiseVolume` | Media player volume up                              | system               |
| `ALT+p`                    | Execute hyprpicker to extract hex code              |                      |
| `ALT+SUPER+F`              | Fullscreen window                                   |                      |
| `ALT+SUPER+T`              | Toggle floating                                     |                      |
| `ALT+SUPER+X`              | Maximize window                                     |                      |
| `ALT+SUPER+m`              | Minimize Window                                     |                      |
| `ALT+SUPER+mouse:272`      | Move a window with left click                       |                      |
| `CTRL+SUPER+e`             | Open the power menu (wlogout)                       |                      |
| `CTRL+SUPER+j`             | Scroll this column to the next thing                | system               |
| `CTRL+SUPER+k`             | Scroll this column to the previous thing            | system               |
| `SHIFT+left`               | Dofus: previous team member                         | contextual           |
| `SHIFT+right`              | Dofus: next team member                             | contextual           |
| `SHIFT+ALT+TAB`            | Alt-tab: previous window                            |                      |
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
| `SUPER+semicolon`          | Close focused window (or its whole group)           |                      |
| `SUPER+slash`              | Show keybind cheatsheet                             | system               |
| `SUPER+space`              | Which-key…                                          | system               |
| `SUPER+t`                  | Open a project (picker)                             | system               |
| `SUPER+x`                  | Cycle the workspace layout                          | system               |

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
| `SHIFT+escape` | Leave the whole tree, back to the base submap |                      |
| `SUPER+f`      | Open the floating Terminal                    |                      |

## `which` submap

14 binds.

| Key            | Does                                          | Where it should live |
| -------------- | --------------------------------------------- | -------------------- |
| `a`            | Applications                                  |                      |
| `c`            | Configuration                                 |                      |
| `d`            | Dofus                                         | contextual           |
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
| `ALT+h`        | Resize vertically by -20                      |                      |
| `ALT+j`        | Resize horizontally by -20                    |                      |
| `ALT+k`        | Resize horizontally by 20                     |                      |
| `ALT+l`        | Resize vertically by 20                       |                      |
| `SHIFT+escape` | Leave the whole tree, back to the base submap |                      |
