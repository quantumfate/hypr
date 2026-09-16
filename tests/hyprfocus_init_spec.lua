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
  version = 1,
  base = {
    workspaces = { "code", "gaming", "media", "logs" },
    bindings = { "root", "dofus", "llm", "media" },
    services = { "obsidian" },
    projects = {},
    scenes = {
      gaming = { bindings = { "dofus", "media" } },
      code = { bindings = { "llm" } },
    },
  },
  modes = {
    neutral = { name = "Neutral" },
    game = {
      name = "Gaming",
      workspaces = { only = { "gaming", "logs" } },
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
