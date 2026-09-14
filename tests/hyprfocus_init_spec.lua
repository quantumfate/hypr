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

local function fresh(declaration, pointer)
  local stub = require("tests.hl_stub").new()
  _G.hl = stub
  for _, mod in ipairs({
    "hypr.lib.store",
    "hypr.hyprfocus.binds",
    "hypr.hyprfocus.workspaces",
    "hypr.hyprfocus.init",
  }) do
    package.loaded[mod] = nil
  end

  -- The store is a file on disk; stub the handle rather than the filesystem,
  -- so these specs stay about the wiring instead of about JSON.
  local stores = { hyprfocus = declaration, focus = pointer or { mode = "neutral" } }
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
      }
    end,
  }

  local binds = require("hypr.hyprfocus.binds")
  binds.reset()
  local handles = {}
  stub.bind = function(key)
    local handle = { key = key, enabled = true }
    function handle:set_enabled(value)
      self.enabled = value
    end
    handles[#handles + 1] = handle
    return handle
  end
  stub.define_submap = function(_, fn)
    fn()
  end
  binds.capture()
  stub.bind("SUPER, t")
  for _, name in ipairs({ "dofus", "llm" }) do
    stub.define_submap(name, function()
      stub.bind("a")
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
    t.eq("llm", table.concat(report.bindings_disabled, ","))
    t.eq("code,media", table.concat(report.workspaces_withdrawn, ","))
    t.eq(false, rules.code.enabled)
    t.eq(true, rules.gaming.enabled)
  end)

  t.it("refuses to withdraw a workspace that still holds windows", function()
    local stub, hyprfocus, rules = fresh(DECLARATION)
    stub.get_windows = function()
      return { { address = "0x1", workspace = { id = 1, name = "code" } } }
    end
    local report = hyprfocus.apply("game")
    t.eq("code", table.concat(report.workspaces_refused, ","))
    t.eq(true, rules.code.enabled, "a workspace with windows stays reachable")
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
