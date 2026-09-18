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
