# Agent instructions

## Operating model

This desktop is a scene-driven system.

The active **scene**, **time**, and **mood mode** may determine:

- Theme, wallpaper, translucency, information density, and motion
- Allowed applications and actions
- Window state, placement, grouping, and layout
- Class-aware and mode-scoped keybindings
- Notification routing and filtering
- Background work, services, and sync behavior

Unavailable actions may intentionally do nothing without warning. This is
deliberate: availability should become legible through the current interface and
mode.

Study mode may block AI coding tools such as OpenCode or Claude. Vibe Coding is
a separate, visually distinct mode.

## Model routing

Read the Linear issue's `Model tier` label before starting.

Named models for each tier live in [LEO-169](https://linear.app/quantumfate/issue/LEO-169). Do not copy that table here.

- **Frontier**
  - Use a frontier model.
  - Required for architecture, security, systemd/service lifecycle, state
    machines, cross-repository changes, migrations, dependency strategy, or
    ambiguous failures.
  - Research first. Return a detailed plan and risks before implementation.

- **Standard**
  - Use a capable implementation model.
  - Appropriate for bounded implementation with clear acceptance criteria.
  - Confirm scope, implement, test, and document.

- **Fast**
  - Use a lower-cost model only for mechanical, focused, low-risk work.
  - Suitable for small config edits, narrow tests, formatting, or documentation
    corrections.
  - Escalate immediately if dependencies, architecture, or failure modes become
    unclear.

If no model tier exists:

- Use Frontier for architecture or security.
- Use Standard for normal implementation.
- Use Fast only for demonstrably mechanical work.

## Required planning process

Before changing code:

1. Read the Linear issue, its project, milestone, linked issues, and relevant
   module documentation.
2. Identify affected repositories, modules, scenes, modes, machine profiles,
   services, and configuration.
3. Check current behavior before proposing a replacement.
4. Preserve existing contracts unless the issue explicitly changes them.
5. For Frontier work, present a plan before implementation.
6. Do not invent requirements, dependencies, acceptance criteria, or UI
   behavior.

## Context lives in module documentation

Context awareness is managed in the documentation, not in memory or session
notes. Every module owns a Markdown document next to it; documents are modular
and cross-linked, so what an agent needs is always one deliberate link away —
never a search through code to rediscover an invariant someone already wrote
down.

- **Before touching a module, read its document first.** The doc is the
  contract; the code is one implementation of it.
- Each module's doc lives NEXT to the module (`bin/Readme.md`, `docs/scenes.md`,
  `AGENTS.md`), so discovery is local by construction.
- Documents link to their neighbours rather than duplicating architecture
  explanations — follow links deliberately instead of re-reading code to
  reconstruct what a link would have said.
- Update the documentation in the SAME change as the behavior it describes; a
  doc left behind is a defect, not a note.
- Durable decisions land in the Linear issue (and the module doc when they
  define long-term behavior). Comments carry progress, not contracts.
- A module with no doc should get one with its first meaningful change — the
  absence of documentation is the cue to write the contract sentence.

## Documentation is context

Documentation is part of the architecture.

- Keep module documentation close to the module it describes.
- Link related Markdown documents rather than duplicating architecture
  explanations.
- Update documentation when behavior, configuration, state contracts, bindings,
  or integration boundaries change.
- Record decisions in the Linear issue description when they define durable
  behavior.
- Use comments for progress and discussion, not as the only location for
  important decisions.

## Machine profiles

Use explicit machine profiles for screen-dependent behavior:

- `quantum-desktop`
  - Ultrawide layouts may use dedicated regions, intentional gaps, and visible
    wallpaper.

- `quantum-laptop`
  - Smaller displays must fit or float windows without clipping, overlap, or
    desktop-sized geometry.

Any issue involving geometry, widgets, layouts, or display-dependent behavior
must verify both applicable profiles.

## Window scenes and groups

Hyprland owns window state, placement, grouping, and layouts.

- Scenes define deterministic behavior from the current workspace and matching
  windows.
- A scene may define position, size, opacity, blur, grouping, layout,
  bindings, and visual context.
- Groups are class-scoped.
- A group must reject windows whose class is not explicitly allowed.
- Admission guards must apply to keyboard actions, mouse-driven drops, and
  focus-driven paths.
- Tmux groups accept only tmux-role windows.
- Dofus groups accept only Dofus windows.
- Ad-hoc terminals remain floating or slide in from the bottom.
- Prefer reusable scene and group rules over application-specific exceptions.
- A scene-worthy abstraction owns its bindings: if a class or concept is modeled
  as a scene, its binding tree travels with it. Do not leak scene-specific
  actions into generic submaps such as `shell`; the which-key overlay must
  render only the keys the current mode admits.
- The target model (focus mode → scene set → monitor; scenes with bring-up,
  teardown and window-state behaviour) is
  [docs/desktop-model.md](docs/desktop-model.md). Read it before any scene,
  mode, workspace or binding work. It is mostly not implemented yet; do not
  assume a behaviour exists because that document describes it.

## Keybindings and which-key

Maintain three keybinding classes. The intent is defined in
[docs/desktop-model.md](docs/desktop-model.md#bindings); it overrides older
wording elsewhere.

1. **System-level**
   - Always available; never withheld.
   - Escape hatches, exits, compositor and window controls, system-centric
     actions. Not individual Quickshell widgets owned by another module.

2. **Contextual**
   - Available while a matching window is **focused**.
   - Common actions across applications via the app's API or CLI.
   - Never keyed on scenes or workspaces.

3. **Mode-scoped**
   - Owned by a **scene**, not by the mode declaration.
   - Available while the scene is active in the current mode and its workspace
     is focused. Trees of a mode's scenes merge; a conflict is a validation
     error.

Which-key follows Neovim: holding the main modifier for more than 1.5 s opens
it; `SUPER+Space` is the leader for domain-specific trees.

Which-key must render the runtime-enabled set by construction.

- Never show bindings that cannot execute.
- Withholding a submap also withholds its entry path.
- Do not allow users to enter an empty or unavailable submap.
- Keep the current context path visible.
- Prefer human-readable key labels.
- Preserve generous spacing, readable grouping, and laptop-safe layout.

## Mood policies and services

Mood modes are policy-bearing operating states.

Policies may allow, modify, defer, or suppress:

- Notifications
- Application launches
- Background tasks
- Sync services
- Widget availability
- Window scenes and binding trees

Protect general-operating system units.

Scene-managed applications and services may stop or start cooperatively:

- Never forcefully terminate unfinished work.
- Request a transition first.
- Let services finish necessary work or defer shutdown.
- Use systemd restart behavior where appropriate.
- A delayed restart after a mode switch is acceptable.
- Send lifecycle outcomes to the logging workspace.

Critical vault-access or security alerts must bypass mood filtering.

## Theme and application adapters

Quickshell owns presentation. Hyprland owns compositor behavior. Scripts and
adapters own external application integration.

For every themed application, document:

- Configuration source
- Live reload behavior
- Relaunch-required behavior
- Next-login-required behavior
- Error and pending-state behavior

Theme switching must report honestly what changed immediately, what requires
relaunch, and what requires login.

Do not rely on shell environment for graphical applications under UWSM. Respect
systemd user-manager environment boundaries.

## Dependencies and bootstrap

When a change introduces a dependency, service, environment variable, generated
file, or machine configuration:

- Update the associated System Config Ansible playbook in the same deliverable.
- Ensure bootstrap can reproduce the required environment.
- Document any manual setup that cannot be automated.
- Do not mark the issue complete until the dependency path is verified.

## Verification and completion

Before marking work complete:

- Verify every explicit acceptance criterion.
- Add or update tests, fixtures, benchmarks, or health checks when relevant.
- Verify desktop and laptop behavior for geometry-dependent work.
- Verify scene transitions, mode changes, service restarts, and failure behavior
  where applicable.
- Update module and architecture documentation.
- Update the Linear issue with decisions, verification evidence, changed
  dependencies, and remaining risks.
- Compositor behaviour stubs cannot see (rule timing, groups, specials,
  monitors, mode switches) is verified with `just e2e`: scenarios in a nested
  Hyprland with a sandboxed store and the `e2e` host
  ([tests/e2e/Readme.md](tests/e2e/Readme.md)). Never probe the live session
  in its place.
- Do not silently widen scope. Create or propose follow-up issues for
  additional work.

## Read order

New to the repo, read in this order — each layer points at the next:

1. [README.md](README.md) — what this is, how to install it.
2. [ARCHITECTURE.md](ARCHITECTURE.md) — the packaging model: dual delivery (Nix + Ansible), repo scope, ecosystem coupling, release channels.
3. [docs/scenes.md](docs/scenes.md) — the scene contract (below is the enforcement; this is the reasoning). [docs/shelves.md](docs/shelves.md) — the shelf submap for apps that never tile.
4. [docs/lifecycle.md](docs/lifecycle.md) — the window lifecycle: current behaviour per stage and the draft contract.
5. [bin/Readme.md](bin/Readme.md) — the shell helpers the desktop spawns, and the state/IPC seams to the quickshell sibling repo.
6. [system-config/docs/bindings.md](../system-config/docs/bindings.md) — the
   binding architecture (LEO-303): system-level / contextual / mode-scoped
   keybinds, and why a withheld tree takes its door and rendering with it.
7. Cross-repo: `system-config/docs/hyprfocus.md` (the full `hyprfocus` engine)
   and quickshell `ARCHITECTURE.md` (shared state + IPC). This repo is one
   executor of declarations those repos also execute.

## Repo map

| Path                     | Owns                                                                 |
| ------------------------ | -------------------------------------------------------------------- |
| `hypr/`                  | the running compositor logic (Lua); scene engine under `hypr/scene/` |
| `*.conf`                 | hypr\* daemon configs (hypridle, hyprlock, hyprpaper, …)             |
| `bin/`                   | the `,name.sh` helpers binds and quickshell spawn                    |
| `conf/`                  | host-specific data (`workspace_specs`, temporary `scenes` fork)      |
| `etc/`                   | generated/contract data (`scene-managed.json`, systemd targets)      |
| `session/`               | uwsm env, systemd user units, greeter fragment                       |
| `flake.nix` / `ansible/` | the two delivery paths (kept in sync, both first-class)              |
| `tests/`                 | Lua specs (`tests/run.lua` + `hl_stub.lua`) and shell-helper tests   |

## Contract

Scenes are a **document**. Engines execute it. Do not add per-feature merge, `barred`, or spawn code.

Read [docs/scenes.md](docs/scenes.md) before touching window placement, grouping, or workspace layout.

**A scene owns its workspace; a mode selects scenes.** A scene declares which windows belong, how they sit (it is the layout), its bring-up/teardown, its window-state behaviour and its mode-scoped bindings. A **mode** selects the active scenes, their monitors and the theme, and calls scene bring-up/teardown. See [docs/desktop-model.md](docs/desktop-model.md). The engine as a whole is `hyprfocus`; the cross-repo architecture lives in the sibling `system-config/docs/hyprfocus.md`.

- Keyed by workspace `default_name` (`code`, `gaming`). Workspace ids are host data in `workspace_specs`.
- The scene **is** the layout (`hl.layout.register`), not a corrector running on top of one. Order is the order boxes are placed; share is a fraction of `ctx.area`. Neither is a dispatched correction.
- `group = true` on a member match = one Hyprland group of **only those classes**. Fold matches in; eject foreigners. Never `lock` (it rejects later same-class members).
- Derive a block's group each pass — the group already holding the most of its tiles wins. Do not remember a membership set: it cannot recover from `auto_group` splitting a block in two.
- Companion windows: member `spawn`. Mode-scoped binding trees are owned by scenes and admitted with them; contextual trees follow the focused window — never filtered after the fact.
- A mode selects scenes; it does not arrange windows or own binding trees.

Lua surface (`hypr/events/scene.lua`; the engine itself is layered under `hypr/scene/`):

```lua
Scene.active(ws)           -- name or nil
Scene.tile(name, match)    -- first tile of that match, or nil
```

The one scene table is the hyprfocus declaration's `base.scenes` (`$QF_STORE/hyprfocus.json`; `QF_STORE` defaults to `$XDG_STATE_HOME/quantum-store` and env-hyprland exports it). Geometry, compile, companions, bindings and the resolver all read it. It is seeded by `,hyprfocus seed` from quickshell's `assets/hyprfocus.default.json`; hypr ships no scene seed. A missing declaration leaves the scene engine inert and sends a notification. The retired `scenes.json` is folded in once (`hypr/scene/migrate.lua`: only scenes that differ from the retired seed) and renamed to `scenes.json.migrated`.

## Hyprland primitives (do not rediscover)

The Lua API has object and handle interfaces that make the dispatcher workarounds unnecessary. Reach for these first.

- **`hl.layout.register(name, provider)`** — `recalculate(ctx)` gets `ctx.area` and `ctx.targets`, each with `target:place(box)`. This is how geometry is decided. The compositor calls it on every change, so no event subscription is needed and none should be added.
- **`HL.Group:add(window)` / `:remove(window)`** — window-targeted grouping. No adjacency, no hops.
- **`set_enabled`** on the handles returned by `hl.bind`, `hl.window_rule`, `hl.workspace_rule` and `hl.layer_rule` — rules and binds are admitted and withdrawn at runtime, with no config reload.
- `auto_group` can still swallow foreigners; runtime eject is required even after compiling `set always` / `barred`.
- A window rule matched on another rule's effect (e.g. `match = { tag = "..." }` where that tag is stamped by a rule matched on `workspace = "name:<ws>"`) never fires from that chain: the feeding rule's own `workspace` match is not true yet when the window opens, so its tag lands after open and the dependent rule never sees it (spiked live, LEO-369). Compile-time `group`/`barred`/`deny` effects chained off a workspace-scoped tag never fire; decide them at runtime instead.

Only if none of the above fits:

- Positioning **dispatchers** act on the **focused** window, so they need a focus-dance (focus → dispatch → restore), which makes geometry depend on focus. Avoid.
- `movewindow` at a monitor edge **moves the window to the adjacent monitor**. It is not usable for ordering.
- A corrective loop over another layout cannot be made stable: it must guess which events matter, measure animated geometry, and steal focus to act. That approach was tried and retired; do not reintroduce it.

## Commands

```sh
just check                         # fmt + tests + luacheck (the gate)
just test                          # lua tests/run.lua + the shell helpers' tests
TEST_SPECS='tests/scene_layout_spec.lua tests/scene_spec.lua' lua tests/run.lua
just fmt
just units                         # regenerate etc/systemd targets the contract names
```

Tests use `tests/hl_stub.lua`. `require` of event modules self-wires; specs `fresh()` the stub and drain timers. Do not assume a live compositor.

## Style

- Match neighboring Lua: complete-sentence `--` comments, no new comment noise.
- `stylua` + `luacheck` must stay clean.
- Do not mention issue trackers in docs or commit messages.
- Do not invent a second scene table, a second 0.67, or a Dofus-only group guard.
- Grouping is declared once, by the scene, and compiled to rules. Do not hand-write a `group` key for a class a block already names.
