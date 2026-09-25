-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- Group adapter order (LEO-380): `hypr/scene/group_adapters.lua`'s registry
--- decides `mod+j/k`'s walk order inside a group. Points `QF_STORE` at a
--- scratch dir first, same as `tests/store_spec.lua`, since the Dofus
--- adapter reads the roster off the shared store.
local t = require("tests.harness")

local dir = t.tempdir()
local real_getenv = os.getenv
os.getenv = function(k)
  if k == "QF_STORE" then
    return dir
  end
  if k == "XDG_STATE_HOME" then
    return dir .. "/legacy"
  end
  return real_getenv(k)
end

local Store = require("hypr.lib.store")
local group_adapters = require("hypr.scene.group_adapters")

local function member(address, title)
  return { address = address, title = title }
end

t.describe("group_adapters.for_class", function()
  t.it("returns the default adapter for an unregistered class", function()
    t.eq(group_adapters.default, group_adapters.for_class("Kitty-Main"))
    t.eq(group_adapters.default, group_adapters.for_class(nil))
  end)

  t.it("returns the Dofus adapter for Dofus.x64", function()
    t.ok(group_adapters.for_class("Dofus.x64") ~= group_adapters.default)
  end)
end)

t.describe("default adapter: stable join order", function()
  t.it("falls back to the members' own order with no recorded joins", function()
    local order = group_adapters.default.order({ member("0x1"), member("0x2") }, { group_key = "0x1" })
    t.eq({ "0x1", "0x2" }, order)
  end)

  t.it("orders by recorded join order once members have joined", function()
    group_adapters.record_join("g1", "0x2")
    group_adapters.record_join("g1", "0x1")
    local order = group_adapters.default.order({ member("0x1"), member("0x2") }, { group_key = "g1" })
    t.eq({ "0x2", "0x1" }, order)
  end)

  t.it("appends a present member that was never recorded", function()
    group_adapters.forget("g2")
    group_adapters.record_join("g2", "0x1")
    local order = group_adapters.default.order({ member("0x1"), member("0x2") }, { group_key = "g2" })
    t.eq({ "0x1", "0x2" }, order)
  end)

  t.it("drops a member that left without dropping the rest", function()
    group_adapters.forget("g3")
    group_adapters.record_join("g3", "0x1")
    group_adapters.record_join("g3", "0x2")
    group_adapters.record_join("g3", "0x3")
    group_adapters.record_leave("g3", "0x2")
    local order = group_adapters.default.order({ member("0x1"), member("0x3") }, { group_key = "g3" })
    t.eq({ "0x1", "0x3" }, order)
  end)

  t.it("record_order replaces the record with the physical group order", function()
    group_adapters.forget("g5")
    group_adapters.record_join("g5", "0x1")
    group_adapters.record_join("g5", "0x2")
    group_adapters.record_order("g5", { "0x2", "0x1" })
    local order = group_adapters.default.order({ member("0x1"), member("0x2") }, { group_key = "g5" })
    t.eq({ "0x2", "0x1" }, order)
  end)

  t.it("forget drops the whole recorded order", function()
    group_adapters.record_join("g4", "0x1")
    group_adapters.forget("g4")
    local order = group_adapters.default.order({ member("0x2"), member("0x1") }, { group_key = "g4" })
    t.eq({ "0x2", "0x1" }, order)
  end)
end)

t.describe("default adapter: enter picks the last-focused member", function()
  t.it("is nil with nothing recorded", function()
    local address = group_adapters.default.enter({ member("0x1"), member("0x2") }, { group_key = "e1" })
    t.eq(nil, address)
  end)

  t.it("picks the recorded member if it is still present", function()
    group_adapters.record_focus("e2", "0x2")
    local address = group_adapters.default.enter({ member("0x1"), member("0x2") }, { group_key = "e2" })
    t.eq("0x2", address)
  end)

  t.it("is nil once the recorded member has left", function()
    group_adapters.record_focus("e3", "0x2")
    local address = group_adapters.default.enter({ member("0x1") }, { group_key = "e3" })
    t.eq(nil, address)
  end)

  t.it("forget drops the recorded focus along with the join order", function()
    group_adapters.record_focus("e4", "0x1")
    group_adapters.forget("e4")
    local address = group_adapters.default.enter({ member("0x1"), member("0x2") }, { group_key = "e4" })
    t.eq(nil, address)
  end)
end)

t.describe("Dofus adapter: enter keeps the default (no obvious override)", function()
  t.it("is the same function as the default adapter's", function()
    t.eq(group_adapters.default.enter, group_adapters.for_class("Dofus.x64").enter)
  end)
end)

t.describe("Dofus adapter: team roster order", function()
  local store = Store.define("dofus/team")

  t.it("orders present windows by the selected team's roster", function()
    store:put({
      selected = "pioneer",
      title_prefix = "Dofus ",
      teams = { pioneer = { "Iop", "Eniripsa", "Sram" } },
    })
    local members = { member("0x3", "Dofus Sram"), member("0x1", "Dofus Iop"), member("0x2", "Dofus Eniripsa") }
    local order = group_adapters.for_class("Dofus.x64").order(members)
    t.eq({ "0x1", "0x2", "0x3" }, order)
  end)

  t.it("appends a member outside the roster, sorted by address", function()
    store:put({
      selected = "pioneer",
      title_prefix = "Dofus ",
      teams = { pioneer = { "Iop" } },
    })
    local members = { member("0x2", "Dofus Stray"), member("0x1", "Dofus Iop") }
    local order = group_adapters.for_class("Dofus.x64").order(members)
    t.eq({ "0x1", "0x2" }, order)
  end)
end)

t.describe("the project adapter", function()
  ---@param address string
  ---@param role string?
  ---@return table
  local function slot(address, role)
    -- Hyprland renders its own tags with a trailing `*`; carry that, so the
    -- spec exercises the shape the live window table actually hands over.
    return { address = address, title = address, tags = role and { "slot:" .. role .. "*" } or {} }
  end

  t.it("is chosen by the class pattern, whatever the project is called", function()
    t.eq(true, group_adapters.for_class("Proj-hypr") ~= group_adapters.default)
    t.eq(true, group_adapters.for_class("Proj-security-and-privacy") ~= group_adapters.default)
    t.eq(true, group_adapters.for_class("Kitty-Main") == group_adapters.default)
  end)

  t.it("sits the tabs in template order, not the order they spawned", function()
    local members = { slot("0x4", "run"), slot("0x1", "zsh"), slot("0x2", "nvim"), slot("0x3", "yazi") }
    local order = group_adapters.for_class("Proj-hypr").order(members, { group_key = "0x1" })
    t.eq({ "0x2", "0x3", "0x1", "0x4" }, order)
  end)

  t.it("puts a declared scope after the template, in join order", function()
    local members = { slot("0x9", "test"), slot("0x2", "nvim"), slot("0x1", "zsh") }
    local order = group_adapters.for_class("Proj-hypr").order(members, { group_key = "k" })
    t.eq({ "0x2", "0x1", "0x9" }, order)
  end)

  t.it("leaves a member still being stamped at the end rather than dropping it", function()
    local members = { slot("0x8", nil), slot("0x2", "nvim") }
    local order = group_adapters.for_class("Proj-hypr").order(members, { group_key = "k" })
    t.eq({ "0x2", "0x8" }, order)
  end)
end)

return t
