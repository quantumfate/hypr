-- Test fixtures stub the runtime: partial store handles the type system cannot prove.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field
--- The one-time fold of the retired `scenes.json` into the declaration's
--- `base.scenes`, and the loader that reads only the declaration.
local t = require("tests.harness")

local DOFUS = {
  blocks = { { classes = { "Dofus.x64" }, group = true, order = 1, share = 0.67 } },
  strays = "float",
}

t.describe("scene migrate", function()
  local migrate = require("hypr.scene.migrate")

  t.it("fingerprints ignore empty tables and key order", function()
    local a = { blocks = { { classes = { "x" }, order = 1 } }, barred = {}, bindings = {} }
    local b = { bindings = {}, blocks = { { order = 1, classes = { "x" } } } }
    t.eq(migrate.fingerprint(a), migrate.fingerprint(b))
  end)

  t.it("drops scenes still equal to the retired seed", function()
    local seed = { dofus = migrate.fingerprint(DOFUS) }
    local declaration = { base = { scenes = { dofus = { blocks = {} } } } }
    local out, folded = migrate.fold(declaration, { scenes = { dofus = DOFUS } }, seed)
    t.eq(0, #folded)
    t.eq(0, #out.base.scenes.dofus.blocks)
  end)

  t.it("folds edited and unknown scenes into base.scenes", function()
    local seed = { dofus = migrate.fingerprint(DOFUS) }
    local edited = { blocks = { { classes = { "Dofus.x64" }, order = 1, share = 0.5 } } }
    local out, folded = migrate.fold({}, { scenes = { dofus = edited, extra = { blocks = {} } } }, seed)
    t.eq("dofus,extra", table.concat(folded, ","))
    t.eq(0.5, out.base.scenes.dofus.blocks[1].share)
  end)

  t.it("a missing legacy document folds nothing", function()
    local _, folded = migrate.fold({ base = { scenes = {} } }, nil)
    t.eq(0, #folded)
  end)
end)

t.describe("scene spec loader", function()
  local function load_with(stores, legacy_path)
    local stub = require("tests.hl_stub").new()
    _G.hl = stub
    package.loaded["hypr.scene.spec"] = nil
    package.loaded["hypr.lib.store"] = {
      define = function(name)
        return {
          path = name == "scenes" and legacy_path or nil,
          get = function()
            return stores[name]
          end,
          put = function(_, doc)
            stores[name] = doc
          end,
        }
      end,
    }
    local scenes = require("hypr.scene.spec").load()
    package.loaded["hypr.scene.spec"] = nil
    package.loaded["hypr.lib.store"] = nil
    return scenes, stub
  end

  t.it("reads scenes from the declaration's base.scenes", function()
    local scenes = load_with({ hyprfocus = { base = { scenes = { dofus = DOFUS } } } })
    t.eq(0.67, scenes.dofus.blocks[1].share)
  end)

  t.it("is inert and notifies when the declaration is missing", function()
    local scenes, stub = load_with({ hyprfocus = {} })
    t.eq(nil, next(scenes))
    local notified = false
    for _, cmd in ipairs(stub.exec_cmds) do
      notified = notified or cmd:find("no scene declaration", 1, true) ~= nil
    end
    t.eq(true, notified, "a missing declaration is reported")
  end)

  t.it("folds an edited legacy store once and moves it aside", function()
    local dir = os.tmpname()
    os.remove(dir)
    local legacy = dir .. "-scenes.json"
    local f = assert(io.open(legacy, "w"))
    f:write("{}")
    f:close()
    local edited = { blocks = { { classes = { "Dofus.x64" }, order = 1, share = 0.5 } } }
    local stores = { hyprfocus = { base = { scenes = { dofus = DOFUS } } }, scenes = { scenes = { dofus = edited } } }
    local scenes = load_with(stores, legacy)
    t.eq(0.5, scenes.dofus.blocks[1].share)
    t.eq(nil, io.open(legacy, "r"), "the legacy store is moved aside")
    local moved = io.open(legacy .. ".migrated", "r")
    t.eq(true, moved ~= nil)
    moved:close()
    os.remove(legacy .. ".migrated")
  end)
end)
