--- The transition planner: desired desk + running state -> ordered steps.
---
--- Pure, so these are plain tables. The planner deciding correctly is what the
--- announce phase shows the user and what the executor carries out, so a wrong
--- plan is a wrong desk regardless of how well the execution works.
local t = require("tests.harness")
local plan = require("hypr.hyprfocus.plan")

local function desk(over)
  local d = {
    mode = over.mode or "game",
    workspaces = over.workspaces or {},
    services = over.services or {},
    bindings = over.bindings or {},
    projects = over.projects or {},
    revoke = over.revoke or {},
    scenes = {},
    notify = {},
  }
  return d
end

local function running(over)
  over = over or {}
  return {
    workspaces = over.workspaces or {},
    services = over.services or {},
    bindings = over.bindings or {},
    projects = over.projects or {},
    held = over.held,
  }
end

---"action kind:name" for each step, so order is visible in the assertion.
local function trace(p)
  local out = {}
  for i, s in ipairs(p.steps) do
    out[i] = s.action .. " " .. s.kind .. ":" .. s.name
  end
  return table.concat(out, " | ")
end

t.describe("no change", function()
  t.it("plans nothing when the desks already agree", function()
    local p = plan.plan(
      desk({ workspaces = { "code" }, services = { "theme-auto" } }),
      running({ workspaces = { "code" }, services = { "theme-auto" } })
    )
    t.ok(plan.is_empty(p), "expected an empty plan, got: " .. trace(p))
  end)

  t.it("leaves a resource both desks want alone", function()
    -- Switching between two modes that share Obsidian must not stop and
    -- restart it. Diffing complete sets gives this without reference counting.
    local p = plan.plan(
      desk({ mode = "llm", services = { "obsidian", "ollama" } }),
      running({ services = { "obsidian", "theme-auto" } })
    )
    t.eq("retire services:theme-auto | admit services:ollama", trace(p))
  end)
end)

t.describe("ordering", function()
  t.it("gives up before taking on", function()
    -- Running both desks at once, however briefly, is the opposite of what a
    -- mode asked for when its whole point is reclaiming resources.
    local p = plan.plan(desk({ services = { "b" } }), running({ services = { "a" } }))
    t.eq("retire services:a | admit services:b", trace(p))
  end)

  t.it("admits a workspace before the project that opens onto it", function()
    local p = plan.plan(desk({ workspaces = { "study" }, projects = { "obsidian" } }), running({}))
    t.eq("admit workspaces:study | admit projects:obsidian", trace(p))
  end)

  t.it("admits a service before the project that uses it", function()
    -- An app whose backing work is not running yet is an app that looks broken.
    local p = plan.plan(desk({ services = { "obsidian-index" }, projects = { "obsidian" } }), running({}))
    t.eq("admit services:obsidian-index | admit projects:obsidian", trace(p))
  end)

  t.it("revokes dependents before what they depend on", function()
    -- Nothing should be left briefly pointing at something that just left.
    local p = plan.plan(
      desk({}),
      running({ workspaces = { "study" }, services = { "obsidian-index" }, projects = { "obsidian" } })
    )
    t.eq("hold projects:obsidian | retire services:obsidian-index | hold workspaces:study", trace(p))
  end)
end)

t.describe("hold and retire", function()
  t.it("holds windows and retires background work by default", function()
    local p = plan.plan(desk({}), running({ workspaces = { "code" }, services = { "linear-sync" } }))
    t.eq("retire services:linear-sync | hold workspaces:code", trace(p))
  end)

  t.it("honours an explicit revocation override", function()
    local p = plan.plan(desk({ revoke = { code = "retire" } }), running({ workspaces = { "code" } }))
    t.eq("retire workspaces:code", trace(p))
  end)

  t.it("restores what a previous mode held rather than starting it fresh", function()
    -- A held window should come back where it was, not reopen blank.
    local p = plan.plan(desk({ workspaces = { "code" } }), running({ held = { code = "game" } }))
    t.eq("restore workspaces:code", trace(p))
  end)
end)

t.describe("what a transition takes away", function()
  t.it("is the subset the announcement needs", function()
    -- "Entering game mode" should also read as "closing Obsidian, stopping the
    -- sync" — the announcement names resources, not just the mode.
    local p = plan.plan(
      desk({ mode = "game", workspaces = { "gaming" }, services = { "theme-auto" } }),
      running({ workspaces = { "code", "gaming" }, services = { "theme-auto", "linear-sync" } })
    )
    t.eq(2, #p.takes)
    local names = {}
    for _, s in ipairs(p.takes) do
      names[#names + 1] = s.name
    end
    table.sort(names)
    t.eq("code,linear-sync", table.concat(names, ","))
  end)

  t.it("excludes admissions", function()
    local p = plan.plan(desk({ services = { "ollama" } }), running({}))
    t.eq(0, #p.takes, "admitting something takes nothing away")
  end)

  t.it("carries a reason on every step", function()
    local p = plan.plan(desk({ mode = "game" }), running({ services = { "linear-sync" } }))
    t.ok(p.steps[1].why:match("linear%-sync"), p.steps[1].why)
    t.ok(p.steps[1].why:match("game"), "the reason names the mode")
  end)
end)

t.describe("idempotence", function()
  t.it("a plan applied twice is empty the second time", function()
    -- Modelled by applying the plan to the running state and re-planning.
    local target = desk({ mode = "game", workspaces = { "gaming" }, services = { "theme-auto" } })
    local live = running({ workspaces = { "code" }, services = { "linear-sync" } })
    local first = plan.plan(target, live)
    t.ok(not plan.is_empty(first))

    local after = running({ workspaces = { "gaming" }, services = { "theme-auto" } })
    t.ok(plan.is_empty(plan.plan(target, after)), "re-planning an applied plan must do nothing")
  end)
end)

t.describe("rendering", function()
  t.it("prints one line per step", function()
    local p = plan.plan(desk({ services = { "ollama" } }), running({ services = { "linear-sync" } }))
    local lines = plan.lines(p)
    t.eq(2, #lines)
    t.ok(lines[1]:match("^retire%s+services%s+linear%-sync$"), lines[1])
  end)
end)
