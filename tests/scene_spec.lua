-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- The scene engine's wiring (LEO-245): the public surface `hypr/events/scene.lua`
--- exposes, and the static rules `compile.lua` emits from a loaded spec.
---
--- The corrective engine that used to arrange windows here (join/evict/
--- collect via schedule+model+actuator) is retired (LEO-261): geometry now
--- comes only from the registered layout provider, which the compositor
--- calls directly and which is covered by scene_layout_spec/scene_provider_spec.
local t = require("tests.harness")

local GAMING = {
  blocks = {
    { classes = { "Dofus.x64" }, group = true, order = 1, share = 0.67, collect = true },
    { classes = { "zen-gaming-media" }, order = 2, share = 0.33, guard = "deny" },
  },
  barred = { "steam_app_default" },
}

---The scenes document lives in the state store now; the stub hands it over
---the same shape the real store handle answers.
local function define_store(scenes)
  package.loaded["hypr.lib.store"] = {
    define = function()
      return {
        get = function()
          return { version = require("hypr.scene.defaults").version, scenes = scenes }
        end,
        put = function(_, doc)
          scenes = doc.scenes
        end,
      }
    end,
  }
end

---@return table stub
local function fresh(active)
  local stub = require("tests.hl_stub").new()
  _G.hl = stub
  _G.config = { host = { workspaces = { workspace_specs = {} } } }
  define_store({ gaming = GAMING })
  for _, mod in ipairs({ "hypr.scene.spec", "hypr.events.scene" }) do
    package.loaded[mod] = nil
  end

  local windows = {}
  stub.get_windows = function()
    return windows
  end
  stub.get_active_workspace = function()
    return { id = 4, name = active or "gaming" }
  end
  return stub
end

local function win(stub, over)
  local w = {
    address = over.address,
    class = over.class,
    workspace = { id = over.ws_id or 4, name = over.ws or "gaming" },
    floating = over.floating or false,
    at = { x = over.x or 0, y = 0 },
  }
  stub.get_windows()[#stub.get_windows() + 1] = w
  return w
end

t.describe("public surface", function()
  t.it("names the scene on a workspace it owns", function()
    local stub = fresh()
    local M = require("hypr.events.scene")
    t.eq("gaming", M.active({ id = 4, name = "gaming" }))
    t.eq(nil, M.active({ id = 2, name = "code" }))
    t.eq(nil, M.active(nil))
    t.ok(stub)
  end)

  t.it("returns a block's leftmost tile", function()
    local stub = fresh()
    win(stub, { address = "0x2", class = "Dofus.x64", x = 500 })
    win(stub, { address = "0x1", class = "Dofus.x64", x = 0 })
    local M = require("hypr.events.scene")
    t.eq("0x1", M.tile("gaming", { class = "Dofus.x64" }).address)
    t.eq("0x1", M.tile("gaming", "Dofus.x64").address)
    t.eq(nil, M.tile("gaming", "org.kde.kdenlive"))
  end)
end)

t.describe("compiled rules", function()
  t.it("declares grouping once, from the scene", function()
    local stub = fresh()
    require("hypr.scene.compile").emit(require("hypr.scene.spec").load())
    local by_class = {}
    for _, rule in ipairs(stub.window_rules) do
      by_class[rule.match.class] = rule.group
    end
    t.eq("set always", by_class["Dofus.x64"])
    t.eq("deny", by_class["zen-gaming-media"], "the block's own guard, not the default bar")
    t.eq("barred", by_class["steam_app_default"])
  end)
end)
