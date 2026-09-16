# Window lifecycle

Every window passes through six stages: **identify → route → admit → arrange
→ interact → leave**. Scene **bring-up** and **teardown** are driven by the
mode and use the same stages. The intent is
[desktop-model.md](desktop-model.md). The scene schema is
[scenes.md](scenes.md). The cross-repo transition phases are in
`system-config/docs/hyprfocus.md`.

This document has two parts. **Part A** describes what runs today. **Part B**
is a **DRAFT contract that still needs approval**. Nothing in Part B is
decided until the open decisions are settled.

## Part A — Current behaviour

Line numbers refer to the commit that adds this document.

### Stages as implemented

| Stage    | What happens today                                                                                                                                                                                                                                                                                                                                                                         | Where                                                                                                                                                                                                                                                                                                                             | Gaps                                                                                                                                                                                                                                                                                                                                                                   |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| identify | No single step identifies a window. Each mechanism matches the class again for itself, using `spec_lib.block_for` (first block that matches wins) or its own rule `match`.                                                                                                                                                                                                                 | `hypr/scene/spec.lua:159`; `hypr/scene/registry.lua:18` (`claim`); `hypr/events/scene.lua:66` (`scene_for`); `hypr/scene/provider.lua:48`                                                                                                                                                                                         | No tags and no record of the decision. Matching on title or role is not supported. When two blocks match, the first one silently wins.                                                                                                                                                                                                                                 |
| route    | Static workspace targets are written by hand in `windowrules.lua`.                                                                                                                                                                                                                                                                                                                         | `hypr/windowrules.lua:31,40,49,58,74,156,172,194,223,268,277,281,295,369,378`                                                                                                                                                                                                                                                     | Routing is not derived from scenes. Several targets still point at retired names (`name:gaming`, `special:*`). Dynamic instances have no runtime routing step.                                                                                                                                                                                                         |
| admit    | Workspace rules are created once, at load time. A mode resolves to a desk and calls `admit()`, which toggles `set_enabled`. Windows on a withdrawn workspace are moved to `special:hyprfocus-held`. Scene binding trees are admitted on `workspace.active`.                                                                                                                                | `hypr/workspaces.lua:22`; `hypr/hyprfocus/init.lua:199` (`apply`); `hypr/hyprfocus/workspaces.lua:63` (`admit`); `hypr/hyprfocus/hold.lua:65`; `hypr/hyprfocus/resolve.lua:230`; `hypr/events/scene.lua:195`                                                                                                                      | Modes admit workspaces by name, not by scene sets. There is no monitor per scene and no check for two active scenes claiming one class. Scenes have no bring-up. Nothing can create a workspace at runtime.                                                                                                                                                            |
| arrange  | (1) `compile.emit` turns every scene into global class rules (`set always` / `barred`). (2) The scene layout places each tile in `recalculate`. (3) The corrective engine is still wired: on events it arms `schedule` → `model.intent` → `actuator`, which uses focus-dance dispatchers. (4) `solo_gaps` and `layout_opts` rewrite gaps and options on `open_early` / `workspace.active`. | `hypr/scene/compile.lua:16` (called from `hypr/windowrules.lua:448`); `hypr/scene/provider.lua:86`, `hypr/scene/layout.lua:76,168`; `hypr/events/scene.lua:135-192`, `hypr/scene/schedule.lua:106`, `hypr/scene/model.lua:339`, `hypr/scene/actuator.lua:112`; `hypr/events/solo_gaps.lua:137`, `hypr/events/layout_opts.lua:158` | Group rules are global, so a class groups on any workspace. `strays = "float"` is parsed (`layout.lua:217`) but never acted on. Extra windows in a non-group block stack behind its first tile and get no slot (`layout.lua:95`). The single-tile frame is implemented twice (`layout.lua` and `solo_gaps`). The corrective engine and the layout fight over geometry. |
| interact | The binding set is swapped on `workspace.active`. Companion windows are spawned or closed on open, close and move.                                                                                                                                                                                                                                                                         | `hypr/hyprfocus/init.lua:150` (`apply_bindings`); `hypr/scene/companion.lua:41`, `hypr/events/scene.lua:42`                                                                                                                                                                                                                       | There are no window-state behaviours (lock, variant, hand-off, hold-and-return). No explicit float default exists. `moods` and `machines` are parsed (`spec.lua:75-76`) but never used.                                                                                                                                                                                |
| leave    | `registry.forget` runs on close. Companions reconverge across every scene that spawns one. The corrective engine is re-armed. Mode withdrawal holds windows, and a later mode restores them.                                                                                                                                                                                               | `hypr/events/scene.lua:153`; `hypr/hyprfocus/hold.lua:89`                                                                                                                                                                                                                                                                         | Scenes have no teardown. Cooperative veto (hyprfocus phase 3) is not wired for windows. No event is logged.                                                                                                                                                                                                                                                            |

**Logging today:** there is no structured event at any stage.
`hyprfocus.apply` returns a report table, and that is the only record.

### The seven class-matching mechanisms

| #   | Mechanism                                           | Stage(s)         | Proposal                                                                                                                                    | By               |
| --- | --------------------------------------------------- | ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| 1   | `windowrules.lua` workspace targets                 | route            | **Retire** the workspace targets. App properties stay. Routing comes from scenes instead.                                                   | LEO-353          |
| 2   | `scene/compile.lua` global group rules              | arrange          | **Replace** with rules scoped by tags (`scene:`/`block:`), so a class groups only on its own scene's workspace.                             | LEO-354          |
| 3   | `scene/provider.lua` + `layout.lua`                 | arrange          | **Keep**. This is the single place geometry is decided. Extend it to handle strays and extra block windows.                                 | LEO-355, LEO-357 |
| 4   | `scene/model.lua` + `schedule.lua` + `actuator.lua` | arrange          | **Retire**. It duplicates the layout and needs focus-dance.                                                                                 | LEO-261          |
| 5   | `scene/companion.lua`                               | interact / leave | **Replace**. It becomes part of scene bring-up and teardown and stops being an event side-channel.                                          | LEO-360          |
| 6   | `hyprfocus/*` (admit, hold)                         | admit, leave     | **Keep** as the admit owner. Change modes to scene sets with a monitor each, add validation, and add runtime creation of dynamic instances. | LEO-358, LEO-329 |
| 7   | `events/solo_gaps.lua` + `layout_opts.lua`          | arrange          | **Retire**. Framing and options become branches inside the scene layout (the `columns` layout is the only other layout).                    | LEO-357          |
| —   | Logging for all of the above                        | all              | **New**. See the event schema below.                                                                                                        | LEO-352          |
| —   | Window-state behaviours and transitions             | interact         | **New**, pending design.                                                                                                                    | LEO-359          |

## Part B — Proposed contract (DRAFT, pending approval)

### Principles

- Each stage has one owner and is a **pure decision function** with a thin
  executor. The decision returns a **record**. The executor acts on that record
  and logs it.
- Identity is decided **once**, when the window is identified, and is carried
  on Hyprland window tags. Later stages read the tags and never match the class
  again.
- The registry is keyed by window address. The PID is only logged.
- Geometry is decided only by the registered layout (`scene` or `columns`).
  Nothing dispatches geometry fixes.

### Decision record (common shape)

Every stage emits one record with these fields:

```text
ts, trace, stage, event, decision, reason,
class, initial_class, title, pid, address, tags,
scene, block, workspace, workspace_id, monitor, mode, layout
```

- `trace` is fixed per window: it is the address plus the time the window
  opened.
- `decision` is a short verb, for example `route`, `refuse`, `float`, `hold`.
- `reason` is a stable machine token followed by free text.

**Decision needed:** where the log goes. Option (a): append JSONL under
`QF_STORE`, tailed by `logview` on the `logs` workspace. Option (b): the
systemd journal with structured fields. This follows hyprfocus phase 6,
"log every decision, appended".

### Stages

| Stage    | Owner (proposed)                                              | Inputs                                                        | Output (record)                                                                                           | Failure / refusal                                                                                                                                                                                                                                                                                                                                                                                              | Events                                                                      |
| -------- | ------------------------------------------------------------- | ------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| identify | `hypr/scene/identify.lua` (new, pure) + tag executor          | window (class, initial_class, title, role); active scene set  | `{scene, block, tags=[scene:<n>, block:<n>/<b>]}` or `{scene=nil}`                                        | **No match**: the window gets no scene tag and goes to the float default. **Ambiguous within one scene**: a declaration error that validation refuses; the runtime keeps first-match and logs `identify.ambiguous`. **Claimed by several scenes**: only scenes in the active set count, and validation guarantees at most one. **Decision needed:** whether matching uses `initial_class` or the live `class`. | `identify.matched`, `identify.unmatched`, `identify.ambiguous`              |
| route    | `hypr/scene/route.lua` (new)                                  | identify record; mode's scene→monitor map; workspace registry | `{workspace, workspace_id, monitor}`                                                                      | Scene not active: **Decision needed:** leave the window where it opened, or send it to the nameless workspace (LEO-329). Static targets are compiled at load for fixed workspaces. Dynamic instances are routed at runtime.                                                                                                                                                                                    | `route.static`, `route.dynamic`, `route.none`                               |
| admit    | `hypr/hyprfocus/` (`resolve` + `workspaces` + `validate`)     | mode declaration; route record; scene state (lock)            | `{admitted: bool}` for the window. For a mode: `{scenes:[{name,monitor}], refused:[…]}`                   | **Mode validation**: two active scenes claiming one class means the whole mode is refused before anything changes (`admit.mode_refused`). **Window**: a locked scene refuses the window, which is routed to float or the hold area (see interact). **Workspace withdraw with windows**: refused, as today.                                                                                                     | `admit.mode_refused`, `admit.window`, `admit.window_refused`                |
| arrange  | `hypr/scene/provider.lua` + `layout.lua` (`scene`), `columns` | layout targets with tags; scene spec; machine profile         | one box per target, including strays and every window of a block. Logged once per change, not every frame | Target without a block tag: `strays` decides (`slot` \| `float`). A layout that is not `scene`/`columns`: refused at load. It never dispatches.                                                                                                                                                                                                                                                                | `arrange.placed`, `arrange.stray`                                           |
| interact | scene window-state machine (new, LEO-359)                     | admitted open/close events on the scene's workspace; tags     | `{from, to, trigger}` transition, or `none`                                                               | No behaviour defined for the window: **float**. A transition target that is not in the finite table is a declaration error.                                                                                                                                                                                                                                                                                    | `interact.transition`, `interact.hold`, `interact.return`, `interact.float` |
| leave    | scene state machine + registry                                | close / move-out event; address                               | `{scene, block, released, returns:[address]}`                                                             | A held window whose origin scene is gone falls back to float on its current workspace, and this is logged.                                                                                                                                                                                                                                                                                                     | `leave.closed`, `leave.moved`                                               |

### Scene bring-up / teardown (mode-driven sub-stages of admit and leave)

| Call                      | Caller     | Returns                                     | Refusal                                                                                                                                                                                                                                                                                  | Events                                     |
| ------------------------- | ---------- | ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| `scene.up(name, monitor)` | mode enter | `ok \| partial{missing} \| refused{reason}` | `partial` means the mode is still entered and the missing launches are logged. The companion `spawn` moves here.                                                                                                                                                                         | `admit.scene_up`, `admit.scene_up_refused` |
| `scene.down(name)`        | mode exit  | `ok \| veto{reason}`                        | Cooperative: windows are never killed. A veto leaves the scene up and recorded, and the mode is still entered (hyprfocus phase 3). Held windows and locks must resolve first. **Decision needed:** whether a vetoed scene keeps its workspace admitted in the new mode, or is only held. | `leave.scene_down`, `leave.scene_veto`     |

**Decision needed:** whether bring-up launches apps missing from the usual set,
or only arranges windows that already exist.

### Window-state transitions (within interact)

| Behaviour       | Trigger                         | Effect                                     | Exit                                |
| --------------- | ------------------------------- | ------------------------------------------ | ----------------------------------- |
| lock            | the scene declares `lock`       | admit refuses further windows              | the scene goes down                 |
| variant         | declared window opens           | same workspace, alternate layout           | trigger window closes               |
| hand-off        | declared window opens           | workspace becomes named scene B            | declared in B (see open question)   |
| hold-and-return | declared window needs the space | the displaced window goes to the hold area | trigger closes → the window returns |
| float (default) | no behaviour matches            | window floats                              | —                                   |

**Decision needed:** whether the hold area is a per-scene special workspace or
the shared `special:hyprfocus-held`.

### Open question — arrival as intent (NOT decided here)

When a window arrives that another scene claims, is that arrival intent to
evolve the workspace into that scene? A naive rule recurses. Two finite options
are proposed below; this draft picks neither. The final decision belongs to
LEO-359.

| Option                     | Rule                                                                                                                                                                                          | Why it stays finite                                                                 | Cost                                       |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- | ------------------------------------------ |
| **1. Declared edges only** | Arrival is never intent by itself. A scene lists explicit `on_open: {class → scene}` edges, and each target must name its return edge. Validation rejects any cycle longer than one A↔B pair. | The transition graph is declared, static and checked at load, so it is inspectable. | Every evolution must be written by hand.   |
| **2. Depth-1 overlay**     | A claimed arrival can overlay **one** variant/hand-off on top of the base scene, and never a second. Closing the trigger always returns to the base scene. Further arrivals float.            | The state is `base` or `base+overlay`, two states per workspace.                    | Chained evolutions (A→B→C) are impossible. |

**Decision needed:** option 1 or option 2 (or neither, to be decided in LEO-359).

### Decisions carried from the issue (D1–D4, restated — confirm wording)

- **D1 Routing** is derived from scene declarations. Fixed workspaces get
  static rules at load. Dynamic instances get a runtime step (LEO-329).
  `windowrules.lua` holds only app properties.
- **D2 Grouping**: a class groups only on its scene's workspace. Identity is
  carried by `scene:<name>` / `block:<scene>/<block>` tags set when the window
  is identified. The registry is keyed by address, and the PID is only logged.
- **D3 Layouts**: the scene is the layout. `columns` (at least 2 columns, each
  scrolling vertically) is the only other layout. dwindle, master and monocle
  are not used.
- **D4** Every stage emits a structured event.

**Decision needed:** whether the D1–D4 text above matches the approved wording.
