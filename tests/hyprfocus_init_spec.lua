-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- The compositor's half of hyprfocus: read the declaration, apply a mode.
---
--- This is the seam between the pure modules and the running desk, so what is
--- under test is the wiring and the failure behaviour — a bad declaration must
--- report rather than half-apply, and the half of a desk this runtime does not
--- own must be left alone.
local t = require("tests.harness")

local DECLARATION = {
  version = 3,
  base = {
    bindings = { "root", "dofus", "llm", "media" },
    services = { "obsidian" },
    projects = {},
    scenes = {
      gaming = { bindings = { "dofus", "media" } },
      code = { bindings = { "llm" } },
      media = {},
      logs = {},
    },
  },
  modes = {
    neutral = {
      name = "Neutral",
      hidden = true,
      scenes = {
        { name = "code", monitor = "primary" },
        { name = "gaming", monitor = "primary" },
        { name = "media", monitor = "secondary" },
        { name = "logs", monitor = "secondary" },
      },
    },
    game = {
      name = "Gaming",
      scenes = { { name = "gaming", monitor = "primary" }, { name = "logs", monitor = "secondary" } },
      bindings = { remove = { "llm", "media" } },
    },
  },
}

local function fresh(declaration, pointer)
  local stub = require("tests.hl_stub").new()
  _G.hl = stub
  for _, mod in ipairs({
    "hypr.lib.store",
    "hypr.hyprfocus.hold",
    "hypr.hyprfocus.binds",
    "hypr.hyprfocus.workspaces",
    "hypr.hyprfocus.init",
  }) do
    package.loaded[mod] = nil
  end

  -- The store is a file on disk; stub the handle rather than the filesystem,
  -- so these specs stay about the wiring instead of about JSON.
  local stores = {
    hyprfocus = declaration,
    focus = pointer or { mode = "neutral" },
    ["hyprfocus-held"] = {},
  }
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

  local binds = require("hypr.hyprfocus.binds")
  binds.reset()
  stub.bind = function(key)
    local handle = { key = key, enabled = true }
    function handle:set_enabled(value)
      self.enabled = value
    end
    return handle
  end
  stub.define_submap = function(_, fn)
    fn()
  end
  binds.bind("SUPER, t")
  for _, name in ipairs({ "dofus", "llm", "media" }) do
    binds.submap(name, function()
      binds.bind("a")
    end)
  end

  local workspaces = require("hypr.hyprfocus.workspaces")
  workspaces.reset()
  local rules = {}
  for _, name in ipairs({ "code", "gaming", "media", "logs" }) do
    rules[name] = hl.workspace_rule({ workspace = name, default_name = name })
    workspaces.record(name, rules[name])
  end

  return stub, require("hypr.hyprfocus.init"), rules, workspaces
end

t.describe("reading the declaration", function()
  t.it("reports a store holding nothing usable instead of guessing", function()
    -- Guessing here means applying a desk nobody declared.
    local _, hyprfocus = fresh(nil)
    local desk, err = hyprfocus.apply("game")
    t.eq(nil, desk)
    t.ok(err and err:match("no declaration"), tostring(err))
  end)

  t.it("reports an unknown mode rather than applying a blank desk", function()
    local _, hyprfocus = fresh(DECLARATION)
    local report, err = hyprfocus.apply("gamming")
    t.eq(nil, report)
    t.ok(err and err:match("unknown mode"), tostring(err))
  end)

  t.it("reads the active mode from the pointer", function()
    local _, hyprfocus = fresh(DECLARATION, { mode = "game" })
    t.eq("game", hyprfocus.active())
  end)

  t.it("falls back to the resting state when the pointer says nothing", function()
    local _, hyprfocus = fresh(DECLARATION, {})
    t.eq("neutral", hyprfocus.active())
  end)
end)

t.describe("applying", function()
  t.it("withdraws the workspaces and binding trees a mode does not admit", function()
    local _, hyprfocus, rules = fresh(DECLARATION)
    local report = hyprfocus.apply("game")
    local disabled = { table.unpack(report.bindings_disabled) }
    table.sort(disabled)
    t.eq("llm,media", table.concat(disabled, ","))
    t.eq("code,media", table.concat(report.workspaces_withdrawn, ","))
    t.eq(false, rules.code.enabled)
    t.eq(true, rules.gaming.enabled)
  end)

  t.it("holds a workspace's windows so it can actually be withdrawn", function()
    -- Without holding in front of it the withdrawal is refused and silently
    -- does nothing, which looks like the mode simply not working.
    local stub, hyprfocus, rules = fresh(DECLARATION)
    local windows = { { address = "0x1", workspace = { id = 1, name = "code" } } }
    stub.get_windows = function()
      return windows
    end
    local report = hyprfocus.apply("game")
    t.eq(1, report.windows_held)
    t.eq(0, #report.workspaces_refused, "nothing resisted being parked")
    -- Withdrawn in the same pass: the move is dispatched, not performed, so a
    -- second read would still show the window standing where it was.
    t.eq(false, rules.code.enabled, "the emptied workspace was withdrawn")
    t.ok(windows)
  end)

  t.it("gives windows back when a mode admits their workspace again", function()
    local stub, hyprfocus = fresh(DECLARATION)
    local windows = { { address = "0x1", workspace = { id = 1, name = "code" } } }
    stub.get_windows = function()
      return windows
    end
    hyprfocus.apply("game")
    local report = hyprfocus.apply("neutral")
    t.eq(1, report.windows_restored)
  end)

  t.it("restores the full desk on the resting mode", function()
    local _, hyprfocus, rules = fresh(DECLARATION)
    hyprfocus.apply("game")
    local report = hyprfocus.apply("neutral")
    t.eq(0, #report.workspaces_withdrawn)
    t.eq(true, rules.code.enabled)
  end)

  t.it("leaves services and projects to the runtimes that own them", function()
    -- systemd knows what is running; reporting a guess from here would make
    -- the planner act on one.
    local _, hyprfocus = fresh(DECLARATION)
    local running = hyprfocus.running()
    t.eq(0, #running.services)
    t.eq(0, #running.projects)
  end)
end)

t.describe("scene-scoped binding admission (LEO-266)", function()
  t.it("withholds a tree the active scene does not admit", function()
    -- Game mode removes `media` and `llm`; the gaming scene admits `media` but
    -- not `llm`, so `llm` stays withheld on the gaming workspace.
    local _, hyprfocus = fresh(DECLARATION)
    local disabled = hyprfocus.apply_bindings("game", "gaming")
    table.sort(disabled)
    t.eq("llm", table.concat(disabled, ","))
  end)

  t.it("admits a tree the active scene declares even when the mode removes it", function()
    -- Game mode removes `media`, but the gaming scene declares it. On the
    -- gaming workspace `media` stays loaded while `llm` (removed by mode, not
    -- declared by scene) is withheld.
    local _, hyprfocus = fresh(DECLARATION)
    local disabled = hyprfocus.apply_bindings("game", "gaming")
    table.sort(disabled)
    t.eq("llm", table.concat(disabled, ","))
  end)

  t.it("uses union semantics for mode and scene admissions", function()
    -- Game mode removes `llm` and `media`; the code scene declares `llm`.
    -- Union keeps `llm`, and `media` is the only one withheld.
    local _, hyprfocus = fresh(DECLARATION)
    local disabled = hyprfocus.apply_bindings("game", "code")
    table.sort(disabled)
    t.eq("media", table.concat(disabled, ","))
  end)

  t.it("tracks the scene it last applied", function()
    local _, hyprfocus = fresh(DECLARATION)
    hyprfocus.apply_bindings("neutral", "gaming")
    t.eq("gaming", hyprfocus.last_applied_scene())
  end)
end)

t.describe("planning", function()
  t.it("says what would change without changing it", function()
    local _, hyprfocus, rules = fresh(DECLARATION)
    local p = hyprfocus.plan("game")
    t.ok(#p.steps > 0, "expected a plan")
    t.eq(true, rules.code.enabled, "planning must not touch the desk")
  end)

  t.it("reports a bad declaration the same way applying does", function()
    local _, hyprfocus = fresh(nil)
    local p, err = hyprfocus.plan("game")
    t.eq(nil, p)
    t.ok(err)
  end)
end)

t.describe("entering a mode", function()
  t.it("records the mode before doing any of the work", function()
    -- Every other reader learns the mode from the pointer. Writing it after
    -- the work leaves a window where the desk has changed and nothing can say
    -- why it did.
    local stub, hyprfocus = fresh(DECLARATION)
    hyprfocus.enter("game")
    t.eq("game", hyprfocus.active())
    t.ok(stub)
  end)

  t.it("records who asked", function()
    local _, hyprfocus = fresh(DECLARATION)
    hyprfocus.enter("game", "schedule")
    t.eq("game", hyprfocus.active())
  end)

  t.it("hands the services half to the command line", function()
    -- The compositor cannot stop a systemd unit, so a mode change that only
    -- did its own half would leave the desk describing a mode it is not in.
    local stub, hyprfocus = fresh(DECLARATION)
    hyprfocus.enter("game")
    local spawned = false
    for _, d in ipairs(stub.dispatched) do
      if d.name == "dsp.exec_cmd" and tostring(d.args[1]):match("hyprfocus apply game") then
        spawned = true
      end
    end
    t.ok(spawned, "the services half was never asked for")
  end)

  t.it("refuses a mode that cannot resolve, without recording it", function()
    -- A mode the desk cannot reach must not become the mode it believes it is
    -- in; the pointer would then describe a desk that was never applied.
    local _, hyprfocus = fresh(DECLARATION)
    local report, err = hyprfocus.enter("gamming")
    t.eq(nil, report)
    t.ok(err)
    t.eq("neutral", hyprfocus.active(), "the pointer is untouched")
  end)

  t.it("applies this runtime's half", function()
    local _, hyprfocus, rules = fresh(DECLARATION)
    hyprfocus.enter("game")
    t.eq(false, rules.code.enabled)
  end)
end)

t.describe("scene-set refusal", function()
  t.it("refuses a class conflict with a structured record and changes nothing", function()
    local emitted = {}
    local real_trace = package.loaded["hypr.lib.trace"]
    package.loaded["hypr.lib.trace"] = {
      emit = function(record)
        emitted[#emitted + 1] = record
      end,
    }
    local declaration = {
      version = 3,
      base = {
        bindings = {},
        scenes = {
          gaming = { blocks = { { classes = { "zen-gaming-media" }, order = 1 } } },
          logs = { blocks = { { classes = { "zen-gaming-media" }, order = 1 } } },
          code = {},
          media = {},
        },
      },
      modes = DECLARATION.modes,
    }
    local _, hyprfocus, rules = fresh(declaration)
    local report, err = hyprfocus.apply("game")
    package.loaded["hypr.lib.trace"] = real_trace

    t.eq(nil, report)
    t.ok(tostring(err):find("^class_conflict"), tostring(err))
    t.eq(true, rules.code.enabled, "a refused mode withdraws nothing")
    t.eq(1, #emitted, "one refusal record")
    t.eq("mode_refused", emitted[1].event)
    t.eq("zen-gaming-media", emitted[1].class)
    t.eq("gaming,logs", table.concat(emitted[1].scenes, ","))
  end)
end)

t.describe("monitor placement", function()
  local function with_host(monitors, on)
    local saved = rawget(_G, "config")
    _G.config = { host = { primary_monitor = "DP-1", secondary_monitor = "DP-2" } }
    local stub, hyprfocus = fresh(DECLARATION)
    stub.monitors = monitors
    stub.get_workspace = function()
      return { monitor = { name = on } }
    end
    return stub, hyprfocus, function()
      _G.config = saved
    end
  end

  local function moves(stub)
    local out = {}
    for _, d in ipairs(stub.dispatched) do
      if d.name == "dsp.workspace.move" then
        out[#out + 1] = d.args[1].workspace .. ">" .. d.args[1].monitor
      end
    end
    return table.concat(out, ",")
  end

  t.it("moves a scene's workspace to its role's output", function()
    local stub, hyprfocus, restore = with_host({ { name = "DP-1" }, { name = "DP-2" } }, "DP-1")
    local report = hyprfocus.apply("game")
    restore()
    t.eq("name:logs>DP-2", moves(stub), "the mode's role wins over where it stands")
    t.eq("DP-2", report.placements[2].output)
  end)

  t.it("falls back to primary when the role's output is missing, and moves back on return", function()
    local stub, hyprfocus, restore = with_host({ { name = "DP-1" } }, "DP-1")
    local report = hyprfocus.apply("game")
    t.eq("", moves(stub), "already on primary, nothing to move")
    t.eq("monitor_missing", report.placements[2].reason)
    t.eq("DP-1", report.placements[2].output)

    stub.monitors = { { name = "DP-1" }, { name = "DP-2" } }
    hyprfocus.replace()
    restore()
    t.eq("name:logs>DP-2", moves(stub), "re-placed once the monitor returned")
  end)
end)
