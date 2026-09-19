# Live config: what reaches a running desk, and how

LEO-397. The user's standard: a saved/merged change reaches the running desk
without a session restart, and "needs a reload" is a claim to prove, not a
default. This document is that evidence, read from the installed compositor's
own source (`hyprland-git` at `92b82c0c1e4168d93903ec42a2276843bbd84821`, the
commit `hyprctl version` reports), plus what our engine caches, plus what a
live nested instance actually did.

## This build's config is genuinely Lua, not hyprlang

This `hyprland-git` is a fork whose `Config::IConfigManager` has exactly one
implementation, `Config::Lua::CConfigManager` (`src/config/lua/ConfigManager.*`,
`eConfigManagerType::CONFIG_LUA`). `hyprland.lua` is not templated into a
`.conf` file; it is executed directly by an embedded `lua_State`, and `hl.*` /
`hl.dsp.*` are native bindings this fork registers into that state
(`src/config/lua/bindings/`).

## 1. What the compositor watches and re-executes

**The watcher (`src/config/shared/inotify/ConfigWatcher.cpp`)** watches
`Config::mgr()->getConfigPaths()` — not just the entry file. For the Lua
manager, `m_configPaths` starts as `{ m_mainConfigPath }`
(`hyprland.lua`) and grows by one entry per `require()`'d module, via a hook
on `package.searchers[2]` (`src/config/lua/ConfigManager.cpp:574`,
`requireWildcard`/the searcher wrapper around line 217). **Every Lua module
this config `require()`s is watched**, individually, as its own inotify file
watch — not a directory, and not "the entry file only". A file outside the
`require()` graph (read by `io.open`, like our JSON store) is never in this
list and is never watched.

**A reload (`CConfigManager::reload()`, `ConfigManager.cpp:648`) is a full
re-execution**, not a re-read of one file:

1. Clears `package.loaded` for every non-stdlib module.
2. Destroys and rebuilds the entire `lua_State` (`reinitLuaState()`).
3. Re-runs `hyprland.lua` from scratch, so every `require()` re-executes its
   module body top to bottom.
4. Clears animation/workspace/monitor rule trees, window/layer rules, timers,
   held Lua refs, and **all registered Lua layout providers**
   (`clearLuaLayoutProviders()`) before the re-run re-registers them.

Consequence for our engine: **a module-level Lua cache that survives only
until the next `require()` is not a real cache after a reload** — reload
already wipes it. The bug is never "reload doesn't re-run my module"; it is
"nothing tells the compositor to reload in the first place" (see below) and
"reload re-runs the module, but nothing then asks it to redraw" (see part 2).

## 2. What a reload does NOT do: relayout

`postConfigReload()` emits `Event::bus()->m_events.config.reloaded`. Grepping
every listener of that signal in the compositor source
(`src/**`): `XDGOutput` (re-announces outputs), `Hotkey` (revokes protocol
grabs), `Logger` (rechecks log config), `TransferFunction` (re-reads the SDR
EOTF), `LinuxDMABUF`, and — the only layout-adjacent one —
`ScrollingAlgorithm.cpp:620`, which re-parses its own column-width config.
**Nothing calls `recalculate()` for a custom Lua layout.**

`CLuaTiledAlgorithm::recalculate()` (our registered `"scene"` layout,
`src/config/lua/layout/LuaLayoutProvider.cpp`) is only invoked from
`newTarget`/`removeTarget`/`resizeTarget`/`moveTargetInDirection` — i.e. from
window open/close/move/resize, never from `config.reloaded`. **The user's
suspicion was correct and is now proven from source, not inferred**: a reload
re-executes every Lua module, but nothing re-lays-out an already-placed
scene. This is the actual regression, not "a fact of life".

The one forced-recalculate primitive the compositor exposes to Lua is
`layoutMsg` (`CLuaTiledAlgorithm::layoutMsg`, same file): it calls the
provider's optional `layout_msg(ctx, msg)` Lua function if defined, and then
**unconditionally calls `recalculate()` regardless of what that function
returns** — but only if `layout_msg` is a function at all; if the provider
never defined one, it returns before ever reaching that unconditional call.
`layoutMsg` always targets the currently _focused_ workspace
(`LayoutManager::layoutMsg` → `ws->space()->layoutMsg`), so reaching every
scene means visiting each monitor's active workspace.

## 3. What our engine cached, and whether it reached a running desk

| Cache                                                                           | Where                                                                                                                                                                                        | Reached a running desk before this change?                                                                                                                   | Fix                                                                                                                                                                                                                    |
| ------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `hypr/scene/spec.lua`'s normalized scene table                                  | module-level `cache` upvalue, memoized forever within one Lua-state lifetime                                                                                                                 | Only via a full `hyprctl reload` (which wipes the module and re-normalizes) — never from a bare store edit                                                   | Cache keyed on the store handle's mtime (`Handle:mtime()`, new in `hypr/lib/store.lua`); `M.load()` re-normalizes the instant the file's mtime moves, no reload needed                                                 |
| `hypr/scene/provider.lua`'s registered `recalculate`                            | closed over the `scenes` table `M.attach()` passed once, permanently, for the life of the Lua state                                                                                          | Same as above: only a full reload rebuilt the closure                                                                                                        | `recalculate` now calls `spec_lib.load()` itself on every invocation; `M.attach()` passes a resolver function, not a frozen table                                                                                      |
| Scene gaps                                                                      | did not exist — `provider.lua`'s `gaps()` only read the **host** workspace-spec gaps (`conf/host.lua`'s `build()`, itself only re-resolved on a full reload) or the global compositor config | N/A (feature did not exist)                                                                                                                                  | `Scene.Spec` gained `gaps_in`/`gaps_out` (`hypr/scene/spec.lua`); `gaps()` now prefers scene-declared gaps, then host workspace-spec gaps, then global — the user's own compromise, "scene gaps win where they differ" |
| `conf/host.lua`'s `build()` globals (host gaps, monitor roles, workspace specs) | set once per Lua-state lifetime, as a global table                                                                                                                                           | Only via full reload (`build()` re-runs because `conf/host.lua` is `require()`'d from `hyprland.lua`, so it is in `m_configPaths` and re-executes on reload) | No change needed: this **is** watched (a `require()`'d module) and correctly re-executes; 90_live_gaps.sh already covered it                                                                                           |
| Compiled window/workspace rules, registered binds/layouts                       | rebuilt at each module's top level                                                                                                                                                           | Same as host — reload re-executes the whole `require()` graph                                                                                                | No change needed                                                                                                                                                                                                       |
| Drawer launch commands (`hypr/lib/drawer.lua`)                                  | not cached: `M.load()`/`M.decide()` call `handle:get()` fresh on every key press                                                                                                             | Already live (this is the fixed copyq case cited in the issue)                                                                                               | No change needed — cited here as the working pattern the two fixes above now match                                                                                                                                     |
| Store JSON itself (`$QF_STORE/*.json`)                                          | not `require()`'d — read via `io.open` in `hypr/lib/store.lua`                                                                                                                               | **Never watched by the compositor's inotify list** (§1) — a store edit alone never triggers an automatic reload                                              | Not "fixed" (a JSON data file should not become a Lua config path); instead, this is why the caches above had to become live-reading rather than relying on autoreload                                                 |

## 4. Live evidence (nested instance, `tests/e2e/hq`)

- **`tests/e2e/scenarios/90_live_gaps.sh`** (pre-existing): editing
  `conf/base.lua`'s gap numbers (a `require()`'d module) + `hyprctl reload`
  moves already-open windows and updates the compositor's own `general:*`
  gaps and the scene workspace's rule gaps. Confirms §1's watch/re-exec
  claim for host-level, code-declared gaps.
- **`tests/e2e/scenarios/91_scene_gaps_reload.sh`** (new, LEO-397):
  1. Edits `$QF_STORE/hyprfocus.json`'s `base.scenes.grouped.gaps_in`/
     `gaps_out` directly — **no `hyprctl reload`** — then triggers one
     ordinary compositor recalculate (a float-toggle) and asserts the tiled
     windows moved. Proves the declaration-cache fix: a bare store edit now
     reaches geometry with zero reload.
  2. Edits the scene's gaps again and calls `hyprctl reload` with **no**
     window event before or after, and asserts the windows moved to the new
     value anyway. Proves the `config.reloaded` → forced-recalculate fix
     (§2): reload alone now redraws the scene.
     Run: `bash tests/e2e/scenarios/91_scene_gaps_reload.sh` (also included in
     `just e2e`). Both assertions passed live in this session.

## 5. The fix (`hypr/scene/spec.lua`, `hypr/scene/provider.lua`, `hypr/lib/store.lua`)

- `Store.Handle:mtime()` — a public, freshness-checked mtime read, so a
  consumer's own derived-state cache can key off it instead of duplicating
  the store's stat-and-compare logic.
- `hypr/scene/spec.lua`'s `M.load()` now caches against that mtime instead of
  forever: a scene/gaps/block edit invalidates it the moment the file
  changes, independent of any compositor reload.
- `hypr/scene/provider.lua`'s registered layout reads `spec_lib.load()` fresh
  on every `recalculate`, instead of a table frozen at `M.attach()` time.
- `hypr/scene/provider.lua` defines `layout_msg` (always accepts, no-op body)
  so `hyprctl dispatch layoutmsg` reaches this provider's unconditional
  `recalculate()`; `M.recalculate_all()` cycles focus across every monitor
  whose active workspace runs the `"scene"` layout and dispatches it, then
  restores focus. `M.attach()` wires this to `hl.on("config.reloaded", ...)`,
  so a reload — from any cause, not just an explicit gaps edit — now redraws
  every visible scene.
- `Scene.Spec` gained `gaps_in`/`gaps_out`; `provider.lua`'s `gaps()`
  precedence is now scene → host workspace-spec → global, matching the
  user's compromise from the issue.

## What still requires an explicit action, and why

- **A store-only edit still needs _some_ live recalculate trigger** (a window
  open/close/move/resize, or the `config.reloaded` hook above) to actually
  redraw — Lua has no way to invalidate the compositor's own per-workspace
  target list from outside a layout callback. In practice this is not a gap
  a user hits: opening/closing/moving a window is exactly what a desk does
  continuously, and `hl.dispatch(hl.dsp.layout("recalc"))` (what
  `M.recalculate_all()` uses) is available to any code path that wants to
  force it immediately (e.g. a future `,scene-apply`-style hook after a
  declaration write).
- **A code change to a Lua module still needs `hyprctl reload`** (or a
  restart) to be re-executed — the compositor's watcher already fires this
  automatically for every `require()`'d file (§1), so "save and it applies"
  already holds for code today, confirmed by `90_live_gaps.sh` editing
  `conf/base.lua`. Nothing further was needed there.
