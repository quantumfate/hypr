-- Test fixtures stub the runtime and re-require modules with a hand-made store.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
-- The mode-transition bracket (LEO-423): a mode apply must run with compositor
-- animations suspended, then restore whatever was enabled before, and publish
-- the bracket so the shell's scrim can cover the work.
local t = require("tests.harness")

---A fresh stub plus a `hypr.lib.transition` wired to a fake store.
---@return any stub, any transition, table stores
local function fresh()
  local stub = require("tests.hl_stub").new()
  _G.hl = stub
  for _, mod in ipairs({ "hypr.lib.transition", "hypr.lib.hypr", "hypr.lib.store" }) do
    package.loaded[mod] = nil
  end
  local stores = {}
  package.loaded["hypr.lib.store"] = {
    define = function(name)
      return {
        get = function(_, key)
          local data = stores[name]
          if key == nil then
            return data
          end
          return type(data) == "table" and data[key] or nil
        end,
        set = function(_, patch)
          stores[name] = stores[name] or {}
          for k, v in pairs(patch) do
            stores[name][k] = v
          end
        end,
      }
    end,
  }
  return stub, require("hypr.lib.transition"), stores
end

---The settle timer is the one with the bracket's own span; the failsafe
---(8000 ms, armed by every `begin`) is a different timer and never the one a
---spec wants to fire. With several finishes of the same span the LAST one
---armed is the live one.
---@param stub any
---@param ms integer 400 for a plain apply, 4200 for a veiled transition
---@return table
local function settle_timer(stub, ms)
  local found = nil
  for _, handle in ipairs(stub.timers) do
    if handle.opts.timeout == ms then
      found = handle
    end
  end
  if not found then
    error("no settle timer with timeout " .. ms)
  end
  return found
end

---The armed failsafe timer, for specs that exercise it directly. With several
---begins in flight the LAST one armed is the live one.
---@param stub any
---@return table
local function failsafe_timer(stub)
  local found = nil
  for _, handle in ipairs(stub.timers) do
    if handle.opts.timeout == 8000 then
      found = handle
    end
  end
  if not found then
    error("no failsafe timer armed")
  end
  return found
end

---The grace timer armed at a settle: the quiet set is released when it fires.
---@param stub any
---@return table
local function grace_timer(stub)
  return settle_timer(stub, require("hypr.lib.transition").GRACE_MS)
end

t.describe("transition", function()
  t.it("begin suspends animations, drops activation focus, and publishes the bracket", function()
    local stub, transition, stores = fresh()
    stub.config_values["animations.enabled"] = true
    stub.config_values["misc.focus_on_activate"] = true

    transition.begin("gaming")

    t.eq(false, stub.last_config.animations.enabled)
    t.eq(false, stub.last_config.misc.focus_on_activate)
    t.eq(true, stores["hyprfocus.transition"].active)
    t.eq("gaming", stores["hyprfocus.transition"].mode)
    t.eq(400, stores["hyprfocus.transition"].duration_ms)
    t.eq(true, transition.active())
  end)

  t.it("finish restores the previous values once the settle fires", function()
    local stub, transition, stores = fresh()
    stub.config_values["animations.enabled"] = true
    stub.config_values["misc.focus_on_activate"] = true

    transition.begin("gaming")
    transition.finish("gaming")
    settle_timer(stub, 400).cb()

    -- The bracket is over, the desk is still quiet for the grace.
    t.eq(false, stores["hyprfocus.transition"].active)
    t.eq(false, transition.active())
    t.eq(false, stub.last_config.misc.focus_on_activate)

    grace_timer(stub).cb()
    t.eq(true, stub.last_config.animations.enabled)
    t.eq(true, stub.last_config.misc.focus_on_activate)
  end)

  t.it("quiets every declared option and restores each to what was live", function()
    local stub, transition = fresh()
    stub.config_values["misc.mouse_move_focuses_monitor"] = true
    stub.config_values["binds.workspace_back_and_forth"] = true
    stub.config_values["input.follow_mouse"] = 1

    transition.begin("gaming", true)
    for _, entry in ipairs(transition.QUIET) do
      local section, name = entry.key:match("^([^.]+)%.(.+)$")
      t.eq(entry.quiet, stub.last_config[section][name], entry.key .. " is quiet during the bracket")
    end

    transition.finish("gaming")
    settle_timer(stub, 4200).cb()
    grace_timer(stub).cb()
    t.eq(true, stub.last_config.misc.mouse_move_focuses_monitor)
    t.eq(true, stub.last_config.binds.workspace_back_and_forth)
    t.eq(1, stub.last_config.input.follow_mouse)
  end)

  t.it("a begin inside the grace keeps the quiet and the original priors", function()
    local stub, transition = fresh()
    stub.config_values["misc.focus_on_activate"] = true

    transition.begin("work", true)
    transition.finish("work")
    settle_timer(stub, 4200).cb()
    local first_grace = grace_timer(stub)

    -- The live value reads quiet now; a second chain must not adopt it.
    stub.config_values["misc.focus_on_activate"] = false
    transition.begin("gaming", true)
    t.eq(false, first_grace.enabled, "the newer bracket owns the quiet")
    transition.finish("gaming")
    settle_timer(stub, 4200).cb()
    grace_timer(stub).cb()
    t.eq(true, stub.last_config.misc.focus_on_activate)
  end)

  t.it("restores enabled=false when something else had suspended animations", function()
    local stub, transition = fresh()
    stub.config_values["animations.enabled"] = false

    transition.begin("work")
    transition.finish("work")
    settle_timer(stub, 400).cb()
    grace_timer(stub).cb()

    t.eq(false, stub.last_config.animations.enabled)
  end)

  t.it("a genuine transition veils the shell and holds for the full transition", function()
    local stub, transition, stores = fresh()
    stub.config_values["animations.enabled"] = true

    transition.begin("gaming", true)
    t.eq(true, stores["hyprfocus.transition"].present)
    t.eq(4200, stores["hyprfocus.transition"].duration_ms)
    transition.finish("gaming")
    t.eq(4200, settle_timer(stub, 4200).opts.timeout)
    settle_timer(stub, 4200).cb()
    t.eq(false, stores["hyprfocus.transition"].present, "the veil unmaps once the transition settles")
  end)

  t.it("brackets the apply with the open-focus guard, withdrawn when the grace ends", function()
    local stub, transition = fresh()
    stub.config_values["animations.enabled"] = true

    -- The name is registered once at module load (disabled): a rule first
    -- registered after a dynamic hl.config lands inert on the live build.
    t.eq(1, #stub.window_rules)
    local registered = stub.window_rules[1]
    t.eq("hyprfocus-transition-guard", registered.name)
    t.eq(false, registered.enabled)

    transition.begin("gaming", true)
    t.eq(2, #stub.window_rules)
    local raised = stub.window_rules[2]
    t.eq("hyprfocus-transition-guard", raised.name)
    t.eq(true, raised.no_focus)
    -- An explicit `enabled = true` makes the rule inert on the live build;
    -- the raise declaration must leave the key out entirely.
    t.eq(nil, raised.enabled)

    transition.finish("gaming")
    settle_timer(stub, 4200).cb()
    t.eq(2, #stub.window_rules, "still raised through the grace")
    grace_timer(stub).cb()
    t.eq(3, #stub.window_rules)
    local dropped = stub.window_rules[3]
    t.eq("hyprfocus-transition-guard", dropped.name)
    t.eq(false, dropped.enabled)
  end)

  t.it("runs the settle callback only when the transition settles", function()
    local stub, transition = fresh()
    stub.config_values["animations.enabled"] = true
    local ran = 0

    transition.begin("gaming", true, function()
      ran = ran + 1
    end)
    transition.finish("gaming")
    t.eq(0, ran, "not before the settle")
    settle_timer(stub, 4200).cb()
    t.eq(1, ran)
  end)

  t.it("runs settle steps one per timer tick, then concludes", function()
    -- The watchdog kills an hl.timer callback at 50 ms; the settle's work
    -- together crossed it, so each step gets its own tick.
    local stub, transition, stores = fresh()
    local ran = {}
    transition.begin("gaming", true, function()
      return {
        function()
          ran[#ran + 1] = "stand"
        end,
        function()
          ran[#ran + 1] = "land"
        end,
      }
    end)
    transition.finish("gaming")
    settle_timer(stub, 4200).cb()
    t.eq({ "stand" }, ran, "only the first step inside the settle's own tick")
    t.eq(true, stores["hyprfocus.transition"].active, "still bracketed while steps remain")
    settle_timer(stub, 25).cb()
    t.eq({ "stand", "land" }, ran)
    settle_timer(stub, 25).cb()
    t.eq(false, stores["hyprfocus.transition"].active, "concluded after the last step")
  end)

  t.it("holds a declared handler during the bracket, runs it once after", function()
    local stub, transition = fresh()
    local count = 0
    local function handler()
      count = count + 1
    end
    t.eq(false, transition.hold("scene.workspace_active", handler), "outside a bracket it runs live")

    transition.begin("gaming", true)
    t.eq(true, transition.hold("scene.workspace_active", handler))
    t.eq(true, transition.hold("scene.workspace_active", handler), "coalesced")
    transition.finish("gaming")
    settle_timer(stub, 4200).cb()
    t.eq(1, count, "run once, after the settle")
    t.eq(false, pcall(transition.hold, "undeclared.handler", handler), "only declared handlers may be held")
  end)

  t.it("a reload's apply suspends animations without veiling", function()
    local stub, transition, stores = fresh()
    stub.config_values["animations.enabled"] = true

    transition.begin("work")
    t.eq(false, stores["hyprfocus.transition"].present)
    t.eq(400, stores["hyprfocus.transition"].duration_ms)
    transition.finish("work")
    t.eq(400, settle_timer(stub, 400).opts.timeout)
  end)

  t.it("an older settle never re-enables underneath a newer transition", function()
    local stub, transition, stores = fresh()
    stub.config_values["animations.enabled"] = true

    transition.begin("work")
    transition.finish("work")
    local stale = settle_timer(stub, 400)

    transition.begin("gaming")
    transition.finish("gaming")
    stale.cb()

    -- The stale timer bows out at the generation guard.
    t.eq(false, stub.last_config.animations.enabled)
    t.eq(true, stores["hyprfocus.transition"].active)

    settle_timer(stub, 400).cb()
    t.eq(false, stores["hyprfocus.transition"].active)
    grace_timer(stub).cb()
    t.eq(true, stub.last_config.animations.enabled)
  end)

  t.it("arms a failsafe at every begin and stands it down at a legitimate settle", function()
    local stub, transition = fresh()
    stub.config_values["animations.enabled"] = true

    transition.begin("gaming", true)
    local failsafe = failsafe_timer(stub)
    transition.finish("gaming")
    settle_timer(stub, 4200).cb()

    t.eq(false, failsafe.enabled, "a bracket that settled legitimately never needs its failsafe")
  end)

  t.it("progress pushes the failsafe back, so a long apply is not a wedged one", function()
    -- The guard is there for a bracket that STOPPED, not for one that is
    -- taking its time: restoring ten held windows across two deck scenes
    -- outran the fixed 8s, and force-settling drops the settle callback --
    -- the landing on main and the companion reconvergence with it.
    local stub, transition = fresh()
    stub.config_values["animations.enabled"] = true

    transition.begin("work", true)
    local failsafe = failsafe_timer(stub)
    local armed_at = failsafe.fire_at

    stub.clock = stub.clock + 7000
    transition.progress()

    t.eq(true, failsafe.fire_at > armed_at, "the guard is re-armed from now, not from the begin")
    t.eq(true, transition.active(), "and the bracket is still standing")
  end)

  t.it("progress on a settled bracket is a no-op", function()
    local stub, transition = fresh()
    stub.config_values["animations.enabled"] = true
    transition.begin("work", true)
    transition.finish("work")
    settle_timer(stub, 4200).cb()
    transition.progress()
    t.eq(false, transition.active())
  end)

  t.it("force-settles a bracket whose finish never came, and still lands on main", function()
    local stub, transition, stores = fresh()
    stub.config_values["animations.enabled"] = true
    stub.config_values["misc.focus_on_activate"] = true
    local ran = 0
    local hooked = 0
    transition.on_force_settle(function()
      hooked = hooked + 1
    end)

    transition.begin("gaming", true, function()
      ran = ran + 1
    end)
    -- `finish` is never called: a phased step's timer died mid-apply.
    failsafe_timer(stub).cb()

    t.eq(false, transition.active(), "the bracket comes down")
    t.eq(true, stub.last_config.animations.enabled, "settings are restored")
    t.eq(true, stub.last_config.misc.focus_on_activate)
    t.eq(false, stores["hyprfocus.transition"].active, "the shell is told the bracket is over")
    t.eq(1, ran, "the landing still happens: where you are after a swap is never left to chance")
    t.eq(1, hooked, "the apply guard is released, so the next mode change is not refused")
    -- The open-focus guard is withdrawn too.
    local dropped = stub.window_rules[#stub.window_rules]
    t.eq("hyprfocus-transition-guard", dropped.name)
    t.eq(false, dropped.enabled)
  end)

  t.it("a stale failsafe from an older begin cannot settle a newer bracket", function()
    local stub, transition, stores = fresh()
    stub.config_values["animations.enabled"] = true

    transition.begin("work")
    local stale = failsafe_timer(stub)
    transition.begin("gaming", true)
    stale.cb()

    t.eq(true, transition.active(), "the newer bracket stands")
    t.eq(true, stores["hyprfocus.transition"].active)

    -- Its own failsafe settles it instead.
    failsafe_timer(stub).cb()
    t.eq(false, transition.active())
    t.eq(false, stores["hyprfocus.transition"].active)
  end)
end)
