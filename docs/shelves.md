# Shelves

A shelf is a small special workspace that slides in over the current scene
and holds one app the desk depends on but that never takes a tile. "Shelf" is
the user-facing word; internally each one is a declared **drawer** (LEO-363,
[desktop-model.md](desktop-model.md#scene)) — data in the hyprfocus
declaration, not host Lua.

| Shelf    | Key | Class                   | Launch                | Owner scene(s) | Background |
| -------- | --- | ----------------------- | --------------------- | -------------- | ---------- |
| signal   | `s` | `signal`                | `signal-desktop`      | global         | yes        |
| vesktop  | `v` | `vesktop`               | `vesktop`             | global         | yes        |
| music    | `m` | `([Ss]potify)`          | `spotify`             | global         | yes        |
| ckb-next | `k` | `ckb-next`              | `ckb-next`            | global         | no         |
| copyq    | `c` | `com.github.hluk.copyq` | `copyq`               | global         | no         |
| ankama   | `a` | `Ankama Launcher`       | `,ankama-launcher.sh` | `dofus`        | no         |
| lutris   | `l` | `net.lutris.Lutris`     | `lutris`              | `dofus`        | no         |
| steam    | `t` | `steam`                 | `steam`               | `steam-games`  | no         |

## Contract

- **Data:** the hyprfocus declaration's `base.drawers` (keyed by id: `key`,
  `class`, `desc`, `launch`, optional `background`) and each scene's own
  `drawers` array, which assigns drawers to it by reference — one drawer can
  serve several scenes without duplicating its data. `hypr/lib/drawer.lua`
  reads this live off the store (`M.load`) and turns each entry into a `shelf`
  submap key and a window rule. The submap is reached from the leader hub
  (`w`). Nothing host-specific remains in `conf/base.lua`: window geometry
  (float, centered, 60% × 70%) is engine policy in `hypr/lib/drawer.lua`, not
  per-drawer data.
- **One key, everywhere:** a drawer's key is the same key whether it is
  reached globally or inside its owner scene(s) — there is exactly one submap
  entry per drawer id, never a per-scene duplicate.
- **Placement:** a window rule (`initial_class`) sends the app to
  `special:shelf-<id> silent`, floating, centered, 60% × 70% of the monitor.
  `silent` routes the window WITHOUT showing the special (verified live) — an
  app autostarted in the background must not pop its shelf open by itself.
  Rules are registered last in `hypr/windowrules.lua` so they win. The special
  workspace naming (`shelf-<id>`) is unchanged from before the declaration
  moved here, so a live desk's already-routed windows need no migration.
- **Sizing on show:** the rule's `monitor_w`/`monitor_h` are resolved once, at
  map time, and a special has no monitor until it is _shown_ — so an app that
  opened while one monitor was focused kept that monitor's size when its shelf
  was later shown on another (the smaller screen wearing the larger screen's
  size). `hypr/lib/drawer.lua`'s `M.fit` re-sizes and recenters the window
  against the monitor actually showing the shelf, on every show path. Shelf
  rules also carry `no_initial_focus` and `suppress_event = "activate
activatefocus"`: a drawer is a dependency the desk opens for you, never a
  window that pulls input focus.
- **Key press:** if a window of the class exists, toggle its shelf; otherwise
  launch the app (`uwsm app --`, LEO-363: every drawer launch routes through
  `uwsm`; the Ankama launcher's command still goes through Lutris, taken
  verbatim from the declaration) and record a one-shot pending entry keyed by
  the drawer's id (`M.mark_pending`). The shelf is not toggled while
  launching, so a late window never lands on a shelf the press already
  closed. Because the rule routes silently, the launch itself would otherwise
  open invisibly: `M.rules` also wires a `window.open` handler that checks the
  pending set (`M.pending_for`) against the opening window's class, and — for
  the one that matches — shows the shelf (`M.show_decision`) and clears the
  pending entry. No timer: the launch and the window's `window.open` are the
  only two ends. While a launch is pending, `decide` does nothing at all on a
  further press (no launch, no toggle) rather than re-launching.
- **Background bring-up (LEO-363):** a drawer marked `background: true`
  (signal, vesktop, music) launches silently on mode entry when it is
  admitted and not already running or mid-launch (`hypr/lib/drawer.lua`
  `M.bring_up`, called from `hypr/hyprfocus/init.lua`'s `apply_mode` once the
  desk's admitted scenes are known). A launch failure never blocks the mode:
  `exec_cmd` is fire-and-forget, and the bring-up call itself is wrapped in
  `pcall`.
- **Admission (LEO-363):** a scene-owned drawer is admitted through the same
  synthetic-tree mechanism every other scene-scoped binding uses — a
  `drawer:<id>` tree, computed at apply time from the active scene's
  `drawers` list (`hypr/hyprfocus/init.lua` `scene_binding_set`/
  `conditional_binding_set`), replacing the old hand-named
  `shelf-ankama`/`shelf-steam`/`shelf-lutris` trees. A drawer not admitted is
  **absent** from which-key and the bar — never greyed — the same as any
  other withheld tree (`hypr/lib/whichkey.lua` `M.dump` renders only the
  admitted set). A locked scene still admits its drawers: locking only blocks
  tiled admission.
- **Owner scene(s):** a drawer may be assigned to one or more scenes (Ankama
  and Lutris → `dofus`, Steam → `steam-games`). The press first asks to focus
  the active owner scene's workspace (whichever of its owner scenes is in the
  active desk), dispatched only when that workspace is not already the
  active one on the monitor the active mode placed it on — then toggles or
  launches as usual, so the special workspace shows up on that scene's
  monitor instead of wherever the user was focused. `hypr/lib/drawer.lua`'s
  `decide` stays pure for this: it is handed a `ctx` (the applied desk,
  `hyprfocus.output_for`, and `hl.get_monitors()`) and returns the workspace
  to focus, if any, for the submap entry to dispatch. If none of the
  drawer's owner scenes is part of the active mode's desk, no focus is
  dispatched — the shelf opens on the focused monitor, same as a global
  drawer — and the decision is logged (`admit.drawer_refused`). Signal,
  Vesktop, Spotify, ckb-next and copyq stay global: no owner scene, always
  opens on the focused monitor.
- **Trace events (LEO-363):** `admit.drawer_open` (decision `launch` or
  `toggle`) on a press or background bring-up that resolves to opening the
  drawer, `admit.drawer_refused` when none of its owner scenes are in the
  active desk — replacing the earlier single `shelf_owner_not_admitted`
  interact event. Both carry `drawer`, `class`, `scenes`, `mode`.
- **Ignored monitors:** a drawer never opens on a host's ignored monitor. When
  the focused monitor is ignored, the primary is focused first (`decide` and
  `show_decision` return it as `monitor`). A drawer already shown there is
  re-shown on the primary ([scenes.md](scenes.md#ignored-monitors)).
- Signal, Vesktop, Steam, Lutris, Spotify, ckb-next, copyq and the Ankama
  Launcher are no longer scenes or workspaces.
- **Never held:** `hypr/hyprfocus/hold.lua` never parks or restores a window
  standing on a `special:shelf-*` workspace, nor one whose class matches a
  drawer read live off the declaration (`hypr/lib/drawer.lua`'s `M.exempt`,
  reused by both). A mode switch that withdraws a drawer's owner scene must
  not sweep the drawer's app into `special:hyprfocus-held` — the drawer, not
  the mode, owns that app's lifecycle.
