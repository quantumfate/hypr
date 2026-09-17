# Shelves

A shelf is a small special workspace that slides in over the current scene
and holds one app the desk depends on but that never takes a tile. It is the
first implementation of the **drawers** in
[desktop-model.md](desktop-model.md#scene).

| Shelf   | Key | Class               | Opens with            | Admitted            | Owner scene   |
| ------- | --- | ------------------- | --------------------- | ------------------- | ------------- |
| signal  | `s` | `signal`            | `signal-desktop`      | always              | global        |
| vesktop | `v` | `vesktop`           | `vesktop`             | always              | global        |
| ankama  | `a` | `Ankama Launcher`   | `,ankama-launcher.sh` | tree `shelf-ankama` | `dofus`       |
| steam   | `t` | `steam`             | `steam`               | tree `shelf-steam`  | `steam-games` |
| lutris  | `l` | `net.lutris.Lutris` | `lutris`              | tree `shelf-lutris` | `dofus`       |
| music   | `m` | `([Ss]potify)`      | `spotify`             | always              | global        |

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
- **Owner scene:** a shelf may declare `scene` (Ankama and Lutris → `dofus`,
  Steam → `steam-games`), the scene it slides in over. The press first
  focuses the owner scene's workspace (`hl.dsp.focus({ workspace = "name:" ..
scene })`), dispatched only when that workspace is not already the active
  one on the monitor the active mode placed it on — then toggles or launches
  as usual, so the special workspace shows up on that scene's monitor instead
  of wherever the user was focused. `hypr/lib/shelf.lua`'s `decide` stays pure
  for this: it is handed a `ctx` (the applied desk, `hyprfocus.output_for`,
  and `hl.get_monitors()`) and returns the workspace to focus, if any, for the
  submap entry to dispatch. If the owner scene is not part of the active
  mode's desk at all, no focus is dispatched — the shelf opens on the focused
  monitor, same as a global shelf — and the decision is logged
  (`shelf_owner_not_admitted`). Signal, Vesktop and Spotify stay global: no
  `scene`, always opens on the focused monitor.
- Signal, Vesktop, Steam, Lutris, Spotify and the Ankama Launcher are no
  longer scenes or workspaces.
- **Never held:** `hypr/hyprfocus/hold.lua` never parks or restores a window
  standing on a `special:shelf-*` workspace, nor one whose class matches a
  configured shelf (`hypr/lib/shelf.lua`'s `M.exempt`, reused by both). A mode
  switch that withdraws a shelf's owner scene must not sweep the shelf's app
  into `special:hyprfocus-held` — the shelf, not the mode, owns that app's
  lifecycle.

## Not yet

- Scene-assigned shelves (reachable only while a scene is active) and the
  declared `drawer` resource kind in the hyprfocus declaration.
- The rule effect `workspace = "special:…"` shows the shelf when the app opens.
  An app autostarted in the background will slide its shelf in once.
