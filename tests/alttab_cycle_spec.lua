local t = require("tests.harness")
local cycle = require("hypr.services.alttab.cycle")

t.describe("alttab cycle (pure)", function()
  t.it("down is a bare tab", function()
    t.eq({ mods = "", key = "tab" }, cycle.shortcut_for("down"))
  end)

  t.it("up is shift+tab", function()
    t.eq({ mods = "SHIFT", key = "tab" }, cycle.shortcut_for("up"))
  end)
end)
