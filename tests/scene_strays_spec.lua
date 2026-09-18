---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field
--- Pure stray-float decisions (LEO-367): hypr/scene/strays.lua never calls
--- `hl`, so these assert on the returned decision record directly.
local t = require("tests.harness")

_G.hl = require("tests.hl_stub").new()
package.loaded["hypr.scene.strays"] = nil
package.loaded["hypr.scene.layout"] = nil
package.loaded["hypr.scene.spec"] = nil
package.loaded["hypr.scene.home"] = nil
local strays = require("hypr.scene.strays")

local FLOAT_SCENE = {
  name = "capture",
  blocks = { { classes = { "OBS" }, order = 1 } },
  barred = { "steam_app_default" },
  strays = "float",
}

local SLOT_SCENE = {
  name = "code",
  blocks = { { classes = { "Kitty-Main" }, order = 1 } },
  barred = {},
  strays = "slot",
}

---@param over table
local function win(over)
  return {
    address = over.address,
    class = over.class,
    workspace = { id = 4, name = over.ws or "capture" },
    floating = over.floating,
  }
end

t.describe("strays.decide", function()
  t.it("floats an unblocked window on a strays=float scene", function()
    local w = win({ address = "0x1", class = "mpv" })
    local decision = strays.decide(FLOAT_SCENE, w, { w })
    t.eq("float", decision.action)
    t.eq("0x1", decision.window.address)
  end)

  t.it("leaves a block member alone", function()
    local w = win({ address = "0x1", class = "OBS" })
    local decision = strays.decide(FLOAT_SCENE, w, { w })
    t.eq("none", decision.action)
  end)

  t.it("leaves a barred class alone", function()
    local w = win({ address = "0x1", class = "steam_app_default" })
    local decision = strays.decide(FLOAT_SCENE, w, { w })
    t.eq("none", decision.action)
  end)

  t.it("leaves an already-floating window alone", function()
    local w = win({ address = "0x1", class = "mpv", floating = true })
    local decision = strays.decide(FLOAT_SCENE, w, { w })
    t.eq("none", decision.action)
  end)

  t.it("does nothing on a strays=slot scene", function()
    local w = win({ address = "0x1", class = "mpv", ws = "code" })
    local decision = strays.decide(SLOT_SCENE, w, { w })
    t.eq("none", decision.action)
  end)

  t.it("returns none for a window with no workspace", function()
    local decision = strays.decide(FLOAT_SCENE, { address = "0x1", class = "mpv" }, {})
    t.eq("none", decision.action)
  end)

  t.it("does not float a window another active scene claims", function()
    local PROTON = { name = "proton", blocks = { { classes = { "Proton%-Mail" }, order = 1 } } }
    local spec_by_scene = { capture = FLOAT_SCENE, proton = PROTON }
    local active = { capture = true, proton = true }
    local w = win({ address = "0x1", class = "Proton-Mail" })
    local decision = strays.decide(FLOAT_SCENE, w, spec_by_scene, active)
    t.eq("none", decision.action)
  end)

  t.it("still floats a real stray when spec_by_scene/active are given", function()
    local spec_by_scene = { capture = FLOAT_SCENE }
    local active = { capture = true }
    local w = win({ address = "0x1", class = "mpv" })
    local decision = strays.decide(FLOAT_SCENE, w, spec_by_scene, active)
    t.eq("float", decision.action)
  end)
end)
