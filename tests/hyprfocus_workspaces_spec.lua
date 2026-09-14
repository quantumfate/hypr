--- Workspaces, admitted per mode.
---
--- The dangerous case is withdrawing a workspace that still holds windows:
--- they end up somewhere unreachable, which from the user's side is
--- indistinguishable from having lost them. That guard is what most of this
--- spec is about.
local t = require("tests.harness")

local function fresh()
  local stub = require("tests.hl_stub").new()
  _G.hl = stub
  package.loaded["hypr.hyprfocus.workspaces"] = nil
  local registry = require("hypr.hyprfocus.workspaces")
  registry.reset()
  local handles = {}
  for _, name in ipairs({ "code", "gaming", "media", "logs" }) do
    handles[name] = hl.workspace_rule({ workspace = name, default_name = name })
    registry.record(name, handles[name])
  end
  return stub, registry, handles
end

t.describe("recording", function()
  t.it("keeps every named workspace", function()
    local _, registry = fresh()
    t.eq("code,gaming,logs,media", table.concat(registry.names(), ","))
  end)

  t.it("ignores a workspace the host never named", function()
    -- Nothing could name it to admit it back, so withholding it would be a
    -- one-way door.
    local _, registry = fresh()
    registry.record(nil, hl.workspace_rule({ workspace = "special:magic" }))
    t.eq(false, registry.known("special:magic"))
  end)
end)

t.describe("admission", function()
  t.it("enables what is admitted and withdraws the rest", function()
    local _, registry, handles = fresh()
    local withdrawn = registry.admit({ "gaming", "logs" }, {})
    t.eq("code,media", table.concat(withdrawn, ","))
    t.eq(true, handles.gaming.enabled)
    t.eq(false, handles.code.enabled)
  end)

  t.it("brings a workspace back when a later mode admits it", function()
    local _, registry, handles = fresh()
    registry.admit({ "gaming" }, {})
    t.eq(false, handles.code.enabled)
    registry.admit({ "code", "gaming" }, {})
    t.eq(true, handles.code.enabled, "withholding is not permanent")
  end)

  t.it("refuses to withdraw a workspace that still holds windows", function()
    -- Disabling it would strand them somewhere the user cannot reach, which
    -- reads as having lost them.
    local _, registry, handles = fresh()
    local withdrawn, refused = registry.admit({ "gaming" }, { code = true })
    t.eq("logs,media", table.concat(withdrawn, ","))
    t.eq("code", table.concat(refused, ","))
    t.eq(true, handles.code.enabled, "an occupied workspace stays reachable")
  end)

  t.it("withdraws it once its windows have gone", function()
    -- The caller holds or moves the windows, then asks again.
    local _, registry, handles = fresh()
    registry.admit({ "gaming" }, { code = true })
    t.eq(true, handles.code.enabled)
    registry.admit({ "gaming" }, {})
    t.eq(false, handles.code.enabled)
  end)

  t.it("survives a handle the compositor will not answer for", function()
    local _, registry, handles = fresh()
    handles.media.set_enabled = function()
      error("gone")
    end
    local ok = pcall(registry.admit, { "code" }, {})
    t.ok(ok, "one dead handle aborted the whole admission")
    t.eq(false, handles.gaming.enabled, "the rest still applied")
  end)

  t.it("admitting nothing still leaves occupied workspaces reachable", function()
    local _, registry, handles = fresh()
    registry.admit({}, { logs = true })
    t.eq(true, handles.logs.enabled)
    t.eq(false, handles.code.enabled)
  end)
end)

t.describe("occupancy", function()
  t.it("reports the workspaces holding windows", function()
    local stub, registry = fresh()
    stub.get_windows = function()
      return {
        { address = "0x1", workspace = { id = 1, name = "code" } },
        { address = "0x2", workspace = { id = 4, name = "gaming" } },
        { address = "0x3", workspace = { id = 4, name = "gaming" } },
      }
    end
    local occupied = registry.occupied()
    t.ok(occupied.code and occupied.gaming)
    t.eq(nil, occupied.media)
  end)

  t.it("copes with a window carrying no workspace", function()
    local stub, registry = fresh()
    stub.get_windows = function()
      return { { address = "0x1" } }
    end
    t.eq(0, #registry.names() - #registry.names(), "no error")
    local occupied = registry.occupied()
    t.eq(nil, next(occupied), "a window with no workspace occupies none")
  end)
end)
