---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field
--- Pure identity-stamping decisions (LEO-364): hypr/scene/identify.lua never
--- calls `hl`, so these assert on the returned tag directly. The pokemon
--- media-browser case (docs/scenes.md "Ambiguous classes"): two blocks share
--- one class, told apart by a `slot` each declares.
local t = require("tests.harness")

_G.hl = require("tests.hl_stub").new()
package.loaded["hypr.scene.identify"] = nil
package.loaded["hypr.scene.spec"] = nil
local identify = require("hypr.scene.identify")

local POKEMON = {
  name = "pokemon",
  blocks = {
    { classes = { "retroarch" }, order = 1 },
    { classes = { "zen-twilight-media" }, order = 2, slot = "pokemon/chat" },
    { classes = { "zen-twilight-media" }, order = 3, slot = "pokemon/stream" },
  },
}

---@param over table
local function win(over)
  return {
    address = over.address,
    class = over.class,
    tags = over.tags,
    workspace = { id = 5, name = over.ws or "pokemon" },
  }
end

t.describe("identify.assign", function()
  t.it("assigns the first free slot, in block declaration order", function()
    local w = win({ address = "0x1", class = "zen-twilight-media" })
    t.eq("slot:pokemon/chat", identify.assign(POKEMON, w, { w }))
  end)

  t.it("assigns the next slot when the first is already held by a live sibling", function()
    local held = win({ address = "0x1", class = "zen-twilight-media", tags = { "slot:pokemon/chat" } })
    local w = win({ address = "0x2", class = "zen-twilight-media" })
    t.eq("slot:pokemon/stream", identify.assign(POKEMON, w, { held, w }))
  end)

  t.it("returns nil once every slot for the class is already held", function()
    local a = win({ address = "0x1", class = "zen-twilight-media", tags = { "slot:pokemon/chat" } })
    local b = win({ address = "0x2", class = "zen-twilight-media", tags = { "slot:pokemon/stream" } })
    local w = win({ address = "0x3", class = "zen-twilight-media" })
    t.eq(nil, identify.assign(POKEMON, w, { a, b, w }))
  end)

  t.it("returns nil for a window that already carries one of its slots", function()
    local w = win({ address = "0x1", class = "zen-twilight-media", tags = { "slot:pokemon/stream" } })
    t.eq(nil, identify.assign(POKEMON, w, { w }))
  end)

  t.it("returns nil for a class with no slot block", function()
    local w = win({ address = "0x1", class = "retroarch" })
    t.eq(nil, identify.assign(POKEMON, w, { w }))
  end)

  t.it("scopes taken slots to the window's own workspace", function()
    -- A same-class window on another scene's workspace never blocks a slot
    -- here — grouping.lua's own per-workspace scoping rule (LEO-369).
    local other_ws =
      win({ address = "0x1", class = "zen-twilight-media", ws = "dofus", tags = { "slot:pokemon/chat" } })
    local w = win({ address = "0x2", class = "zen-twilight-media" })
    t.eq("slot:pokemon/chat", identify.assign(POKEMON, w, { other_ws, w }))
  end)

  t.it("returns nil without a workspace (not yet landed)", function()
    t.eq(nil, identify.assign(POKEMON, { class = "zen-twilight-media", address = "0x1" }, {}))
  end)
end)

t.describe("identify.assign_for", function()
  t.it("scopes taken slots to the named workspace, not the window's own", function()
    -- A launch-claimed window maps on the media workspace first (the shared
    -- profile's static pin, LEO-412) but competes for the intent scene's
    -- slots: a sibling on the NAMED workspace holds one, a sibling standing
    -- beside it on media never does.
    local media_sibling =
      win({ address = "0x1", class = "zen-twilight-media", ws = "media", tags = { "slot:pokemon/chat" } })
    local w = win({ address = "0x2", class = "zen-twilight-media", ws = "media" })
    t.eq("slot:pokemon/chat", identify.assign_for(POKEMON, w, { media_sibling, w }, "pokemon"))
  end)

  t.it("sees the intent scene's own siblings as taken", function()
    local claimed = win({ address = "0x1", class = "zen-twilight-media", tags = { "slot:pokemon/chat" } })
    local w = win({ address = "0x2", class = "zen-twilight-media", ws = "media" })
    t.eq("slot:pokemon/stream", identify.assign_for(POKEMON, w, { claimed, w }, "pokemon"))
  end)

  t.it("returns nil without the named workspace", function()
    local w = win({ address = "0x1", class = "zen-twilight-media" })
    t.eq(nil, identify.assign_for(POKEMON, w, { w }, nil))
  end)
end)
