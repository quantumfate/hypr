---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- Session-only scroll state (mirrors tests/scene_order_spec.lua's shape for
--- hypr/scene/order.lua). Plain storage, no arithmetic — deck.lua owns
--- clamping.
local t = require("tests.harness")
local deck_scroll = require("hypr.scene.deck_scroll")

t.describe("deck_scroll", function()
  t.it("has no index for a column that never scrolled", function()
    deck_scroll.reset()
    t.eq(nil, deck_scroll.get("code", 1))
  end)

  t.it("stores and returns an index per scene and column", function()
    deck_scroll.reset()
    deck_scroll.set("code", 1, 2)
    deck_scroll.set("code", 2, 1)
    t.eq(2, deck_scroll.get("code", 1))
    t.eq(1, deck_scroll.get("code", 2))
  end)

  t.it("keeps scenes independent", function()
    deck_scroll.reset()
    deck_scroll.set("code", 1, 3)
    t.eq(nil, deck_scroll.get("other", 1))
  end)

  t.it("get_all returns the full column table for one scene", function()
    deck_scroll.reset()
    deck_scroll.set("code", 1, 2)
    deck_scroll.set("code", 2, 4)
    t.eq({ [1] = 2, [2] = 4 }, deck_scroll.get_all("code"))
    t.eq({}, deck_scroll.get_all("empty"))
  end)

  t.it("reset drops every stored index", function()
    deck_scroll.set("code", 1, 2)
    deck_scroll.reset()
    t.eq(nil, deck_scroll.get("code", 1))
  end)
end)

return t
