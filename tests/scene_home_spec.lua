-- The pure re-homing decision (LEO-353): hypr/scene/home.lua.
local t = require("tests.harness")
local home = require("hypr.scene.home")

local PROTON = { name = "proton", blocks = { { classes = { "ProtonMail%-native" }, order = 1 } } }
local OBSIDIAN = { name = "obsidian-linear", blocks = { { classes = { "obsidian" }, order = 1 } } }

local SPECS = { proton = PROTON, ["obsidian-linear"] = OBSIDIAN }
local ACTIVE = { proton = true, ["obsidian-linear"] = true }

local function win(over)
  return {
    address = over.address or "0x1",
    class = over.class,
    tags = over.tags,
    workspace = over.workspace,
    floating = over.floating,
  }
end

t.describe("scene.home", function()
  t.it("moves a claimed window off a scene that does not claim it", function()
    local w = win({ class = "ProtonMail-native", workspace = { name = "obsidian-linear" } })
    local d = home.decide(SPECS, ACTIVE, w)
    t.eq("move", d.action)
    t.eq("proton", d.workspace)
  end)

  t.it("leaves a window already home alone", function()
    local w = win({ class = "ProtonMail-native", workspace = { name = "proton" } })
    t.eq("none", home.decide(SPECS, ACTIVE, w).action)
  end)

  t.it("leaves an unclaimed stray alone", function()
    local w = win({ class = "kitty", workspace = { name = "obsidian-linear" } })
    t.eq("none", home.decide(SPECS, ACTIVE, w).action)
  end)

  t.it("never claims through a scene that is not active in this mode", function()
    local w = win({ class = "ProtonMail-native", workspace = { name = "obsidian-linear" } })
    local d = home.decide(SPECS, { ["obsidian-linear"] = true }, w)
    t.eq("none", d.action)
  end)

  t.it("leaves a window on a special workspace alone", function()
    local w = win({ class = "ProtonMail-native", workspace = { name = "special:hyprfocus-held" } })
    t.eq("none", home.decide(SPECS, ACTIVE, w).action)
  end)

  t.it("leaves a shelf window alone", function()
    local w = win({ class = "ProtonMail-native", workspace = { name = "special:shelf-steam" } })
    t.eq("none", home.decide(SPECS, ACTIVE, w).action)
  end)

  t.it("has nothing to say about a window with no workspace", function()
    local w = win({ class = "ProtonMail-native", workspace = nil })
    t.eq("none", home.decide(SPECS, ACTIVE, w).action)
  end)

  t.it("settles a float it arrives with", function()
    local w = win({ class = "ProtonMail-native", workspace = { name = "obsidian-linear" }, floating = true })
    local d = home.decide(SPECS, ACTIVE, w)
    t.eq("move", d.action)
    t.ok(d.settle, "move carries settle")
  end)

  t.it("does not settle a window that arrives already tiled", function()
    local w = win({ class = "ProtonMail-native", workspace = { name = "obsidian-linear" }, floating = false })
    local d = home.decide(SPECS, ACTIVE, w)
    t.eq("move", d.action)
    t.eq(nil, d.settle)
  end)
end)

t.describe("scene.home slot-tag ownership", function()
  -- The shared-profile desk (LEO-412): dofus/pokemon declare slot blocks for
  -- the profile class, media declares a bare block for it. `home.claim`
  -- must route a slot-tagged window to its slot's scene, never to media's
  -- bare block; a tagless window is media's by default.
  local MEDIA = { name = "media", blocks = { { classes = { "zen-twilight-media" }, order = 1 } } }
  local DOFUS = {
    name = "dofus",
    blocks = {
      { classes = { "Dofus.x64" }, order = 1 },
      { classes = { "zen-twilight-media" }, order = 2, slot = "dofus/browser" },
    },
  }
  local SLOT_SPECS = { media = MEDIA, dofus = DOFUS }
  local SLOT_ACTIVE = { media = true, dofus = true }

  t.it("claims a slot-tagged window for the scene that declared the slot", function()
    t.eq("dofus", home.claim(SLOT_SPECS, SLOT_ACTIVE, "zen-twilight-media", { "slot:dofus/browser" }))
  end)

  t.it("never lets a bare same-class block swallow another scene's slot claim", function()
    local w = win({ class = "zen-twilight-media", tags = { "slot:dofus/browser" }, workspace = { name = "media" } })
    local d = home.decide(SLOT_SPECS, SLOT_ACTIVE, w)
    t.eq("move", d.action)
    t.eq("dofus", d.workspace)
  end)

  t.it("leaves a tagless window for the bare-block scene", function()
    t.eq("media", home.claim(SLOT_SPECS, SLOT_ACTIVE, "zen-twilight-media", nil))
  end)

  t.it("does not claim a slot whose scene is inactive (context survives a reload)", function()
    local w = win({ class = "zen-twilight-media", tags = { "slot:dofus/browser" }, workspace = { name = "media" } })
    t.eq("none", home.decide(SLOT_SPECS, { media = true }, w).action)
  end)

  t.it("treats a double slot stamp as corrupt and falls back to the class-wide search", function()
    local claim = home.claim(SLOT_SPECS, SLOT_ACTIVE, "zen-twilight-media", {
      "slot:dofus/browser",
      "slot:pokemon/chat",
    })
    t.ok(
      claim == "dofus" or claim == "media",
      "either claiming scene may win for corrupted state, got " .. tostring(claim)
    )
  end)
end)
