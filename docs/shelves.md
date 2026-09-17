# Shelves

A shelf is a small special workspace that slides in over the current scene
and holds one app the desk depends on but that never takes a tile. It is the
first implementation of the **drawers** in
[desktop-model.md](desktop-model.md#scene).

| Shelf   | Key | Class               | Opens with            | Admitted            |
| ------- | --- | ------------------- | --------------------- | ------------------- |
| signal  | `s` | `signal`            | `signal-desktop`      | always              |
| vesktop | `v` | `vesktop`           | `vesktop`             | always              |
| ankama  | `a` | `Ankama Launcher`   | `,ankama-launcher.sh` | tree `shelf-ankama` |
| steam   | `t` | `steam`             | `steam`               | tree `shelf-steam`  |
| lutris  | `l` | `net.lutris.Lutris` | `lutris`              | tree `shelf-lutris` |

`m` in the same submap still toggles the music special workspace.

## Contract

- **Data:** `conf/base.lua` `shelves`. `hypr/lib/shelf.lua` turns each entry
  into a `shelf` submap key and a window rule. The submap is reached from the
  leader hub (`w`).
- **Placement:** a window rule (`initial_class`) sends the app to
  `special:shelf-<name>`, floating, centered, 60 % × 70 % of the monitor.
  Rules are registered last in `hypr/windowrules.lua` so they win.
- **Key press:** if a window of the class exists, toggle its shelf; otherwise
  launch the app (`uwsm app --`), and the rule shows it on its shelf. The shelf
  is not toggled while launching, so a late window never lands on a shelf the
  press already closed.
- **Admission:** a shelf with a `tree` is one leaf attributed to that binding
  tree (`SubmapEntry.tree`), so a mode withholds that key alone and which-key
  hides it. The hyprfocus declaration lists the trees in `base.bindings`;
  every mode except `gaming` removes them.
- Signal, Vesktop, Steam, Lutris and the Ankama Launcher are no longer scenes
  or workspaces.

## Not yet

- Scene-assigned shelves (reachable only while a scene is active) and the
  declared `drawer` resource kind in the hyprfocus declaration.
- The rule effect `workspace = "special:…"` shows the shelf when the app opens.
  An app autostarted in the background will slide its shelf in once.
