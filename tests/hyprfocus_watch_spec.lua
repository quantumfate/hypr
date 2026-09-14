-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- The mode pointer watcher: what the shell (or a schedule) writes to the
--- pointer must reach the compositor's half, and a failure must retry rather
--- than silently diverge.
local t = require("tests.harness")

local DECLARATION = {
  version = 1,
  base = {
    workspaces = { "code", "gaming", "media", "logs" },
    bindings = { "root", "dofus", "llm" },
    services = { "obsidian" },
    projects = {},
  },
  modes = {
    neutral = { name = "Neutral" },
    game = {
      name = "Gaming",
      workspaces = { only = { "gaming", "logs" } },
      bindings = { remove = { "llm" } },
    },
  },
}

---@return any stub, any hyprfocus, any watch, table stores, table rules
local function fresh(declaration, pointer)
  local stub = require("tests.hl_stub").new()
  _G.hl = stub
  for _, mod in ipairs({
    "hypr.lib.store",
    "hypr.lib.notify",
    "hypr.hyprfocus.hold",
    "hypr.hyprfocus.binds",
    "hypr.hyprfocus.workspaces",
    "hypr.hyprfocus.init",
    "hypr.hyprfocus.watch",
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
  for _, name in ipairs({ "dofus", "llm" }) do
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

  return stub, require("hypr.hyprfocus.init"), require("hypr.hyprfocus.watch"), stores, rules
end

t.describe("the watcher", function()
  t.it("converges when the shell edits the pointer without asking the compositor", function()
    local _, hyprfocus, watch, stores, rules = fresh(DECLARATION)
    watch.tick()
    t.eq("neutral", hyprfocus.last_applied(), "the first tick converges on the pointer")

    -- What Focus.set does: a pointer edit and nothing else.
    stores.focus = { mode = "game" }
    local applied_now = watch.tick()
    t.eq("game", applied_now)
    t.eq("game", hyprfocus.last_applied())
    t.eq(false, rules.code.enabled)
    t.eq(true, rules.gaming.enabled)
  end)

  t.it("does not re-apply when the pointer matches what is running", function()
    local stub, hyprfocus, watch = fresh(DECLARATION, { mode = "game" })
    watch.tick()
    local before = #stub.dispatched
    local applied_now = watch.tick()
    t.eq(nil, applied_now, "no mode was applied again")
    t.eq(before, #stub.dispatched, "the desk was not touched")
    t.eq("game", hyprfocus.last_applied())
  end)

  t.it("tries again the next tick when an apply fails, instead of drifting", function()
    local _, hyprfocus, watch, stores = fresh(DECLARATION)
    -- A declaration-less store breaks resolution; the tick records no mode.
    stores.hyprfocus = nil
    local applied_now, err = watch.tick()
    t.eq(nil, applied_now)
    t.ok(err and err:match("no declaration"), tostring(err))
    t.eq(nil, hyprfocus.last_applied(), "the failure was not recorded as an application")

    -- Fix the store; the next tick converges — the error was not sticky.
    stores.hyprfocus = DECLARATION
    stores.focus = { mode = "game" }
    applied_now = watch.tick()
    t.eq("game", applied_now)
  end)

  t.it("hands the services half to the command line as well", function()
    -- Convergence is end to end: the watcher mirrors what a keyboard enter
    -- does, including the CLI's half of the transition.
    local stub, _, watch = fresh(DECLARATION, { mode = "game" })
    watch.tick()
    local spawned = false
    for _, d in ipairs(stub.dispatched) do
      if d.name == "dsp.exec_cmd" and tostring(d.args[1]):match("hyprfocus apply game") then
        spawned = true
      end
    end
    t.ok(spawned, "the services half was never asked for")
  end)

  t.it("arms a re-arming poll at start, not a one-shot", function()
    local stub, _, watch = fresh(DECLARATION, { mode = "game" })
    watch.arm()
    t.ok(#stub.timers == 1, "one chain of timers")
    stub.timers[1].cb()
    t.eq("game", require("hypr.hyprfocus.init").last_applied())
    t.ok(#stub.timers == 2, "the tick re-armed itself")
  end)
end)
