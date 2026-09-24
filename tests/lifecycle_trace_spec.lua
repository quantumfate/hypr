-- Lifecycle logging is wired at existing decision points only (LEO-352):
-- hypr/events/scene.lua (window.open) and hypr/hyprfocus/init.lua (mode
-- apply). These specs stub hypr.lib.trace and assert on the decision records
-- it was called with, not on journal/log output — the sink itself is covered
-- by tests/trace_spec.lua.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
local t = require("tests.harness")

---A trace.lua stub that records every emitted record instead of writing
---anything. Batch brackets are pass-throughs: the records are the contract,
---their delivery grouping is not.
---@return table calls, table stub_module
local function trace_stub()
  local calls = {}
  return calls,
    {
      emit = function(record)
        calls[#calls + 1] = record
      end,
      begin_batch = function() end,
      end_batch = function() end,
    }
end

t.describe("scene.lua wiring", function()
  local function fresh_scene()
    local calls, trace_mod = trace_stub()
    package.loaded["hypr.lib.trace"] = trace_mod

    local stub = require("tests.hl_stub").new()
    _G.hl = stub
    _G.config = { host = { workspaces = { workspace_specs = {} } } }

    local scenes = { gaming = { blocks = { { classes = { "Dofus.x64" }, order = 1, share = 1 } } } }
    package.loaded["hypr.lib.store"] = {
      define = function()
        return {
          get = function()
            return { base = { scenes = scenes } }
          end,
          put = function(_, doc)
            scenes = doc.base.scenes
          end,
        }
      end,
    }

    for _, mod in ipairs({
      "hypr.lib.hypr",
      "hypr.scene.spec",
      "hypr.events.scene",
    }) do
      package.loaded[mod] = nil
    end

    local windows = {}
    stub.get_windows = function()
      return windows
    end
    stub.get_active_workspace = function()
      return { id = 4, name = "gaming" }
    end

    require("hypr.events.scene")
    return calls, stub, windows
  end

  t.it("logs identify.matched when window.open matches a scene block", function()
    local calls, stub, windows = fresh_scene()
    local w = {
      address = "0x1",
      class = "Dofus.x64",
      workspace = { id = 4, name = "gaming" },
      floating = false,
      at = { x = 0, y = 0 },
    }
    windows[#windows + 1] = w
    for _, cb in ipairs(stub.event_handlers["window.open"] or {}) do
      cb(w)
    end

    t.eq(1, #calls)
    t.eq("identify", calls[1].stage)
    t.eq("matched", calls[1].event)
    t.eq("route", calls[1].decision)
    t.eq("gaming", calls[1].scene)
    t.eq("0x1", calls[1].trace)
    t.eq("Dofus.x64", calls[1].class)
  end)

  t.it("logs identify.unmatched when no scene claims the class", function()
    local calls, stub, windows = fresh_scene()
    local w = {
      address = "0x2",
      class = "kitty",
      workspace = { id = 4, name = "gaming" },
      floating = false,
      at = { x = 0, y = 0 },
    }
    windows[#windows + 1] = w
    for _, cb in ipairs(stub.event_handlers["window.open"] or {}) do
      cb(w)
    end

    t.eq(1, #calls)
    t.eq("identify", calls[1].stage)
    t.eq("unmatched", calls[1].event)
    t.eq("none", calls[1].decision)
    t.eq(nil, calls[1].scene)
  end)
end)

t.describe("hyprfocus/init.lua wiring", function()
  local DECLARATION = {
    version = 3,
    base = {
      bindings = { "root" },
      services = {},
      projects = {},
      scenes = { code = {}, gaming = {} },
    },
    modes = {
      neutral = {
        name = "Neutral",
        hidden = true,
        scenes = { { name = "code", monitor = "primary" }, { name = "gaming", monitor = "primary" } },
      },
      game = { name = "Gaming", scenes = { { name = "gaming", monitor = "primary" } } },
    },
  }

  local function fresh_hyprfocus()
    local calls, trace_mod = trace_stub()
    package.loaded["hypr.lib.trace"] = trace_mod

    local stub = require("tests.hl_stub").new()
    _G.hl = stub
    for _, mod in ipairs({
      "hypr.lib.store",
      "hypr.hyprfocus.hold",
      "hypr.hyprfocus.binds",
      "hypr.hyprfocus.workspaces",
      "hypr.hyprfocus",
    }) do
      package.loaded[mod] = nil
    end

    local stores = { hyprfocus = DECLARATION, focus = { mode = "neutral" }, ["hyprfocus-held"] = {} }
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

    local binds = require("hypr.hyprfocus.binds")
    binds.reset()
    binds.bind("SUPER, t")

    local workspaces = require("hypr.hyprfocus.workspaces")
    workspaces.reset()
    for _, name in ipairs({ "code", "gaming" }) do
      workspaces.record(name, hl.workspace_rule({ workspace = name, default_name = name }))
    end

    return calls, require("hypr.hyprfocus")
  end

  t.it("logs admitted and withheld workspaces on mode apply", function()
    local calls, hyprfocus = fresh_hyprfocus()
    hyprfocus.apply("game")

    local admitted, withdrawn = {}, {}
    for _, record in ipairs(calls) do
      if record.event == "workspace_admitted" then
        t.eq("admit", record.stage)
        admitted[record.workspace] = true
      elseif record.event == "workspace_withdrawn" then
        t.eq("admit", record.stage)
        withdrawn[record.workspace] = true
      end
    end
    t.ok(admitted.gaming, "gaming was logged as admitted")
    t.ok(withdrawn.code, "code was logged as withdrawn")
  end)
end)
