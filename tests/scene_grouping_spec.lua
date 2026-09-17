---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field
--- Pure group decisions (LEO-369): hypr/scene/grouping.lua never calls `hl`,
--- so these assert on the returned decision record directly.
local t = require("tests.harness")

_G.hl = require("tests.hl_stub").new()
package.loaded["hypr.scene.grouping"] = nil
package.loaded["hypr.scene.spec"] = nil
local grouping = require("hypr.scene.grouping")

local GAMING = {
  name = "gaming",
  blocks = {
    { classes = { "Dofus.x64" }, group = true, order = 1 },
    { classes = { "zen-gaming-media" }, order = 2, guard = "deny" },
  },
  barred = { "steam_app_default" },
}

---@param over table
local function win(over)
  return {
    address = over.address,
    class = over.class,
    workspace = { id = 4, name = over.ws or "gaming" },
    group = over.group,
  }
end

t.describe("grouping.decide", function()
  t.it("does nothing for a lone block window with no peer yet", function()
    local w = win({ address = "0x1", class = "Dofus.x64" })
    local decision = grouping.decide(GAMING, w, { w })
    t.eq("none", decision.action)
  end)

  t.it("seeds when a second ungrouped peer of the same block is live", function()
    local a = win({ address = "0x1", class = "Dofus.x64" })
    local b = win({ address = "0x2", class = "Dofus.x64" })
    local decision = grouping.decide(GAMING, b, { a, b })
    t.eq("seed", decision.action)
    t.eq(2, #decision.members)
    -- Lowest address first, deterministic regardless of which one is `w`.
    t.eq("0x1", decision.members[1].address)
    t.eq("0x2", decision.members[2].address)
  end)

  t.it("joins the group already holding the most block peers", function()
    local group = require("tests.hl_stub").new_group({ win({ address = "0x1", class = "Dofus.x64" }) })
    local grouped_peer = group.members[1]
    local a = { address = "0x1", class = "Dofus.x64", workspace = { name = "gaming" }, group = group }
    local c = win({ address = "0x3", class = "Dofus.x64" })
    t.ok(grouped_peer)

    local decision = grouping.decide(GAMING, c, { a, c })
    t.eq("join", decision.action)
    t.eq("0x1", decision.target.address)
  end)

  t.it("leaves an already-grouped window alone", function()
    local group = require("tests.hl_stub").new_group({})
    local w = win({ address = "0x1", class = "Dofus.x64", group = group })
    group.members = { { address = "0x1" } }
    local decision = grouping.decide(GAMING, w, { w })
    t.eq("none", decision.action)
  end)

  t.it("ejects a foreign window auto_group swallowed", function()
    local group = require("tests.hl_stub").new_group({})
    local w = win({ address = "0x9", class = "steam_app_default", group = group })
    local decision = grouping.decide(GAMING, w, { w })
    t.eq("eject", decision.action)
    t.eq("0x9", decision.window.address)
  end)

  t.it("does nothing for an unrelated class with no group", function()
    local w = win({ address = "0x9", class = "steam_app_default" })
    local decision = grouping.decide(GAMING, w, { w })
    t.eq("none", decision.action)
  end)

  t.it("ignores a peer on a different workspace", function()
    local a = win({ address = "0x1", class = "Dofus.x64", ws = "other" })
    local b = win({ address = "0x2", class = "Dofus.x64" })
    local decision = grouping.decide(GAMING, b, { a, b })
    t.eq("none", decision.action)
  end)

  t.it("returns none for a window with no workspace", function()
    local decision = grouping.decide(GAMING, { address = "0x1", class = "Dofus.x64" }, {})
    t.eq("none", decision.action)
  end)
end)
