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
  version = 3,
  base = {
    bindings = { "root", "dofus", "llm" },
    services = { "obsidian" },
    projects = {},
    scenes = { code = {}, gaming = {}, media = {}, logs = {} },
  },
  modes = {
    neutral = {
      name = "Neutral",
      hidden = true,
      scenes = {
        { name = "code", monitor = "primary" },
        { name = "gaming", monitor = "primary" },
        { name = "media", monitor = "primary" },
        { name = "logs", monitor = "primary" },
      },
    },
    game = {
      name = "Gaming",
      scenes = { { name = "gaming", monitor = "primary" }, { name = "logs", monitor = "primary" } },
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
    "hypr.lib.hypr",
    "hypr.lib.transition",
    "hypr.lib.notify",
    "hypr.hyprfocus.hold",
    "hypr.hyprfocus.binds",
    "hypr.hyprfocus.workspaces",
    "hypr.hyprfocus",
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

  return stub, require("hypr.hyprfocus"), require("hypr.hyprfocus.watch"), stores, rules
end

t.describe("the watcher", function()
  t.it("converges when the shell edits the pointer without asking the compositor", function()
    local stub, hyprfocus, watch, stores, rules = fresh(DECLARATION)
    watch.tick()
    stub:drain()
    t.eq("neutral", hyprfocus.last_applied(), "the first tick converges on the pointer")

    -- What Focus.set does: a pointer edit and nothing else.
    stores.focus = { mode = "game" }
    local applied_now = watch.tick()
    stub:drain()
    t.eq("game", applied_now)
    t.eq("game", hyprfocus.last_applied())
    t.eq(false, rules.code.enabled)
    t.eq(true, rules.gaming.enabled)
  end)

  t.it("does not re-apply when the pointer matches what is running", function()
    local stub, hyprfocus, watch = fresh(DECLARATION, { mode = "game" })
    watch.tick()
    stub:drain()
    local before = #stub.dispatched
    local applied_now = watch.tick()
    t.eq(nil, applied_now, "no mode was applied again")
    t.eq(before, #stub.dispatched, "the desk was not touched")
    t.eq("game", hyprfocus.last_applied())
  end)

  t.it("tries again the next tick when an apply fails, instead of drifting", function()
    local stub, hyprfocus, watch, stores = fresh(DECLARATION)
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
    stub:drain()
    t.eq("game", applied_now)
  end)

  t.it("hands the services half to the command line as well", function()
    -- Convergence is end to end: the watcher mirrors what a keyboard enter
    -- does, including the CLI's half of the transition.
    -- The CLI half is spawned from the settle callback, so let the transition
    -- timers run before checking.
    local stub, _, watch = fresh(DECLARATION, { mode = "game" })
    watch.tick()
    stub:drain()
    local spawned = false
    for _, d in ipairs(stub.dispatched) do
      if d.name == "dsp.exec_cmd" and tostring(d.args[1]):match("hyprfocus apply game") then
        spawned = true
      end
    end
    t.ok(spawned, "the services half was never asked for")
  end)

  t.it("a mode boundary clears the submap stack", function()
    -- A submap entered under the previous mode may belong to a tree this
    -- mode withholds: the way out must not be something the mode takes with
    -- it. Resetting the stack on every converge costs nothing when the stack
    -- is already empty.
    local stub, _, watch, stores = fresh(DECLARATION)
    watch.tick()
    stores.focus = { mode = "game" }
    watch.tick()
    local reset_seen = nil
    for _, d in ipairs(stub.dispatched) do
      if d.name == "dsp.submap" and tostring(d.args[1]) == "reset" then
        reset_seen = true
      end
    end
    t.ok(reset_seen, "the stack is reset at the mode boundary")
  end)

  t.it("attaches event subscriptions, not a clock", function()
    -- The watcher subscribes to the desk's own events instead of paying a
    -- clock tick forever: convergence is a chance the desk already runs.
    local stub, hyprfocus, watch = fresh(DECLARATION, { mode = "game" })
    t.eq(0, #stub.timers, "no timer chain — idle desks pay stats, not ticks")
    watch.attach()
    -- The mode transition arms one-shots only (the animation bracket's
    -- settle plus its failsafe, LEO-423), never a repeating clock.
    local repeating = 0
    for _, timer in ipairs(stub.timers) do
      if timer.opts and timer.opts.type ~= "oneshot" then
        repeating = repeating + 1
      end
    end
    t.eq(0, repeating, "no repeating timer was armed")
    t.ok(#stub.timers <= 2, "at most the transition's one-shot settle and failsafe")
    local handler = stub.event_handlers["workspace.active"]
    t.ok(handler and #handler >= 1, "workspace.active triggers convergence")
    -- The load-time convergence ran the pointer's mode once (after its lead).
    stub:drain()
    t.eq("game", hyprfocus.last_applied())
  end)
end)

t.describe("a gaming -> neutral -> gaming round trip", function()
  -- A compositor that performs the moves it is handed and raises the event a
  -- real one does, so the watcher runs from inside an apply exactly as live.
  local function compositor(stub, windows)
    stub.get_windows = function()
      return windows
    end
    stub.dispatch = function(action)
      stub.dispatched[#stub.dispatched + 1] = action
      if type(action) == "table" and action.name == "dsp.window.move" then
        local args = action.args[1]
        local address = args.window:match("^address:(.+)$")
        for _, w in ipairs(windows) do
          if w.address == address then
            w.workspace = { name = (args.workspace:gsub("^name:", "")) }
            for _, cb in ipairs(stub.event_handlers["window.move_to_workspace"] or {}) do
              cb(w)
            end
          end
        end
      end
    end
  end

  local function where(windows)
    local out = {}
    for _, w in ipairs(windows) do
      out[#out + 1] = w.address .. "@" .. w.workspace.name
    end
    return table.concat(out, " ")
  end

  local HELD_BOTH = "0x1@special:hyprfocus-held 0x2@special:hyprfocus-held 0x3@gaming 0x4@logs"
  local BACK = "0x1@code 0x2@code 0x3@gaming 0x4@logs"

  t.it("brings every held window back and never strands one", function()
    local stub, hyprfocus, watch, stores, rules = fresh(DECLARATION, { mode = "game" })
    local windows = {
      { address = "0x1", class = "kitty", workspace = { name = "code" } },
      { address = "0x2", class = "zen", workspace = { name = "code" } },
      { address = "0x3", class = "Dofus", workspace = { name = "gaming" } },
      { address = "0x4", class = "logs", workspace = { name = "logs" } },
    }
    compositor(stub, windows)
    watch.attach()
    stub:drain()
    t.eq("game", hyprfocus.last_applied())
    t.eq(HELD_BOTH, where(windows))
    t.eq(false, rules.code.enabled)

    stores.focus = { mode = "neutral" }
    t.eq("neutral", watch.tick())
    stub:drain()
    t.eq(BACK, where(windows))
    t.eq(true, rules.code.enabled)
    t.eq({}, stores["hyprfocus-held"].windows, "nothing left in the record")

    stores.focus = { mode = "game" }
    -- `apply` rather than `converge`: the report is what this asserts, and a
    -- genuine transition defers its report (LEO-423).
    local report = hyprfocus.apply("game")
    t.eq(HELD_BOTH, where(windows))
    t.eq(0, report.unreachable)
    t.eq({ ["0x1"] = "code", ["0x2"] = "code" }, stores["hyprfocus-held"].windows, "every held window has its origin")

    stores.focus = { mode = "neutral" }
    report = hyprfocus.apply("neutral")
    t.eq(BACK, where(windows))
    t.eq(2, report.windows_restored)
    t.eq(0, report.unreachable)
  end)

  t.it("refuses an apply nested inside another one", function()
    local stub, hyprfocus = fresh(DECLARATION, { mode = "game" })
    local windows = { { address = "0x1", workspace = { name = "code" } } }
    local nested
    compositor(stub, windows)
    stub.event_handlers["window.move_to_workspace"] = {
      function()
        nested = { hyprfocus.apply("neutral") }
      end,
    }
    hyprfocus.apply("game")
    t.eq("apply already in progress", nested[2])
    t.eq(false, hyprfocus.applying())
  end)

  t.it("rescues a held window with no origin and logs it", function()
    local saved = rawget(_G, "config")
    _G.config = { host = { primary_monitor = "DP-1" } }
    local stub, hyprfocus = fresh(DECLARATION, { mode = "neutral" })
    stub.monitors = { { name = "DP-1", activeWorkspace = { name = "code" } } }
    local windows = { { address = "0x9", workspace = { name = "special:hyprfocus-held" } } }
    compositor(stub, windows)
    local report = hyprfocus.apply("neutral")
    _G.config = saved
    t.eq(1, report.unreachable)
    t.eq("0x9@code", where(windows))
  end)
end)
