-- Test fixtures stub the runtime: partial `hl` objects and lookups the type
-- system cannot prove non-nil. The stub shape is the contract under test.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field
--- LEO-400: a reload must not move focus, and a mode's `main` scene is only
--- ever the fallback, never a periodic correction.
---
--- `M.build`/`M.plan_restore` are pure, so most of this needs no compositor.
--- The dispatch-facing half (`M.capture`/`M.restore`) is exercised through
--- the `hl` stub, the same way `hyprfocus_init_spec.lua` covers its module.
local t = require("tests.harness")

-- store.lua reads QF_STORE via os.getenv; point it at a scratch dir so
-- capture/restore write real files without touching anything real, the same
-- pattern tests/store_spec.lua uses.
local dir = t.tempdir()
local real_getenv = os.getenv
os.getenv = function(k)
  if k == "QF_STORE" then
    return dir
  end
  if k == "XDG_STATE_HOME" then
    return dir .. "/legacy"
  end
  return real_getenv(k)
end

local function fresh()
  package.loaded["hypr.hyprfocus.focus_history"] = nil
  package.loaded["hypr.lib.store"] = nil
  return require("hypr.hyprfocus.focus_history")
end

t.describe("focus_history.build", function()
  t.it("captures every monitor's active workspace, plus what truly holds focus", function()
    local focus_history = fresh()
    local snap = focus_history.build({
      { name = "WAYLAND-1", active_workspace = { name = "code" } },
      { name = "HEADLESS-2", active_workspace = { name = "logs" } },
    }, "code", "0x1")
    t.eq("code", snap.monitors["WAYLAND-1"])
    t.eq("logs", snap.monitors["HEADLESS-2"])
    t.eq("code", snap.focused_workspace)
    t.eq("0x1", snap.focused_window)
  end)

  t.it("skips a monitor with no active workspace yet", function()
    local focus_history = fresh()
    local snap = focus_history.build({ { name = "WAYLAND-1" } }, nil, nil)
    t.eq(nil, snap.monitors["WAYLAND-1"])
  end)
end)

t.describe("focus_history.plan_restore", function()
  t.it("does nothing with no snapshot (first reload ever, nothing captured yet)", function()
    local focus_history = fresh()
    local moves, refocus = focus_history.plan_restore(nil, { { name = "WAYLAND-1" } }, nil, nil, nil)
    t.eq(0, #moves)
    t.eq(nil, refocus)
  end)

  t.it("does nothing when every monitor already shows what was captured", function()
    local focus_history = fresh()
    local snap = { monitors = { ["WAYLAND-1"] = "code" }, focused_workspace = "code" }
    local live = { { name = "WAYLAND-1", active_workspace = { name = "code" } } }
    local moves, refocus = focus_history.plan_restore(snap, live, nil, nil, nil)
    t.eq(0, #moves)
    -- The captured workspace already holds focus, so restoring it is a no-op
    -- decision, not a skipped one -- still reported as the target.
    t.eq("code", refocus.workspace)
  end)

  t.it("restores a monitor the reload silently moved off its workspace", function()
    local focus_history = fresh()
    local snap = { monitors = { ["WAYLAND-1"] = "code" } }
    local live = { { name = "WAYLAND-1", active_workspace = { name = "proton" } } }
    local moves = focus_history.plan_restore(snap, live, nil, nil, nil)
    t.eq(1, #moves)
    t.eq("code", moves[1].workspace)
    t.eq("restore", moves[1].reason)
  end)

  t.it("falls back to main only when the captured workspace is no longer admitted", function()
    local focus_history = fresh()
    local snap = { monitors = { ["WAYLAND-1"] = "retired-scene" } }
    local live = { { name = "WAYLAND-1", active_workspace = { name = "proton" } } }
    local admitted = { code = true, proton = true }
    local moves = focus_history.plan_restore(snap, live, admitted, "code", "WAYLAND-1")
    t.eq(1, #moves)
    t.eq("code", moves[1].workspace)
    t.eq("main_fallback", moves[1].reason)
  end)

  t.it("does nothing for an unadmitted capture with no main seat on that monitor", function()
    local focus_history = fresh()
    local snap = { monitors = { ["WAYLAND-1"] = "retired-scene" } }
    local live = { { name = "WAYLAND-1", active_workspace = { name = "code" } } }
    local admitted = { code = true }
    -- main exists but is placed on a different monitor: LEO-400's outranking
    -- rule (never a guessed jump) means this monitor is left alone.
    local moves = focus_history.plan_restore(snap, live, admitted, "code", "HEADLESS-2")
    t.eq(0, #moves)
  end)

  t.it("restores the exact previously-focused workspace even with no resolved desk yet", function()
    local focus_history = fresh()
    -- Straight after a reload, before anything has resolved a desk again:
    -- `admitted == nil` must not block a plain restore.
    local snap = { monitors = { ["WAYLAND-1"] = "study" }, focused_workspace = "study" }
    local live = { { name = "WAYLAND-1", active_workspace = { name = "code" } } }
    local moves, refocus = focus_history.plan_restore(snap, live, nil, nil, nil)
    t.eq(1, #moves)
    t.eq("study", moves[1].workspace)
    t.eq("study", refocus.workspace)
  end)

  t.it("carries the focused window along when restoring", function()
    local focus_history = fresh()
    local snap = { monitors = { ["WAYLAND-1"] = "code" }, focused_workspace = "code", focused_window = "0xabc" }
    local live = { { name = "WAYLAND-1", active_workspace = { name = "code" } } }
    local _, refocus = focus_history.plan_restore(snap, live, nil, nil, nil)
    t.eq("0xabc", refocus.window)
  end)

  t.it("refocuses main, without a window, when the focused workspace itself is gone", function()
    local focus_history = fresh()
    local snap = { focused_workspace = "retired-scene", focused_window = "0xabc" }
    local admitted = { code = true }
    local _, refocus = focus_history.plan_restore(snap, {}, admitted, "code", "WAYLAND-1")
    t.eq("code", refocus.workspace)
    t.eq(nil, refocus.window)
  end)

  t.it("gives up cleanly when the focused workspace is gone and there is no main", function()
    local focus_history = fresh()
    local snap = { focused_workspace = "retired-scene" }
    local admitted = { code = true }
    local _, refocus = focus_history.plan_restore(snap, {}, admitted, nil, nil)
    t.eq(nil, refocus)
  end)
end)

t.describe("focus_history.capture/restore (dispatch-facing)", function()
  local function stub_env()
    _G.hl = require("tests.hl_stub").new()
    return fresh()
  end

  t.it("capture writes what the compositor currently shows", function()
    local focus_history = stub_env()
    hl.monitors = { { name = "WAYLAND-1", active_workspace = { name = "code" } } }
    hl.get_active_workspace = function()
      return { name = "code" }
    end
    hl.get_active_window = function()
      return { address = "0x1" }
    end
    focus_history.capture()
    local store = require("hypr.lib.store")
    local snap = store.define("hyprfocus.focus_cache"):get()
    t.eq("code", snap.monitors["WAYLAND-1"])
    t.eq("0x1", snap.focused_window)
  end)

  t.it("restore dispatches nothing when the snapshot already matches", function()
    local focus_history = stub_env()
    local store = require("hypr.lib.store")
    store.define("hyprfocus.focus_cache"):update(function()
      return { monitors = { ["WAYLAND-1"] = "code" }, focused_workspace = "code" }
    end)
    hl.monitors = { { name = "WAYLAND-1", active_workspace = { name = "code" } } }
    hl.dispatched = {}
    focus_history.restore(nil, function()
      return nil
    end)
    -- Still one dispatch: reasserting the same focused workspace/window is
    -- harmless and keeps the executor's logic uniform (no separate
    -- "already correct" branch to keep in sync with `plan_restore`).
    t.eq(1, #hl.dispatched)
  end)

  t.it("restore moves a drifted monitor back and refocuses the captured window", function()
    local focus_history = stub_env()
    local store = require("hypr.lib.store")
    store.define("hyprfocus.focus_cache"):update(function()
      return {
        monitors = { ["WAYLAND-1"] = "code" },
        focused_workspace = "code",
        focused_window = "0xabc",
      }
    end)
    hl.monitors = { { name = "WAYLAND-1", active_workspace = { name = "proton" } } }
    hl.get_windows = function()
      return { { address = "0xabc" } }
    end
    hl.dispatched = {}
    focus_history.restore(nil, function()
      return nil
    end)
    -- Filtered to the focus dispatches: a restore also logs via
    -- `trace.emit`, which dispatches its own `exec_cmd` in between.
    local focuses = {}
    for _, d in ipairs(hl.dispatched) do
      if d.name == "dsp.focus" then
        focuses[#focuses + 1] = d
      end
    end
    t.eq(2, #focuses)
    t.eq("name:code", focuses[1].args[1].workspace)
    t.eq("address:0xabc", focuses[2].args[1].window)
  end)
end)
