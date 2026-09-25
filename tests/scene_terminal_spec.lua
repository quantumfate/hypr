-- Test fixtures stub the runtime: partial `hl` objects and lookups the type
-- system cannot prove non-nil.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- Which terminal class `mod+return` opens (hypr/lib/scene_terminal.lua): the
--- scene's own where it declares one, the plain terminal everywhere else.
local t = require("tests.harness")
local scene_terminal = require("hypr.lib.scene_terminal")

local CODE = {
  name = "code",
  blocks = {
    { classes = { "Proj-hypr" }, order = 1, group = true },
    { classes = { "Kitty-code" }, order = 2 },
  },
}
local PROTON = {
  name = "proton",
  blocks = { { classes = { "proton-mail" }, order = 1 } },
}

t.describe("scene_terminal.declares", function()
  t.it("is true for a scene that admits its own terminal class", function()
    t.eq(true, scene_terminal.declares(CODE, "code"))
  end)

  t.it("is false for a scene that declares no terminal of its own", function()
    t.eq(false, scene_terminal.declares(PROTON, "proton"))
  end)

  t.it("is false for a scene whose terminal class names a DIFFERENT scene", function()
    -- `Kitty-code` on the knowledge workspace is code's terminal, not this
    -- scene's: a class belongs to exactly one scene per mode.
    t.eq(false, scene_terminal.declares(CODE, "knowledge"))
  end)

  t.it("survives a scene with no blocks at all", function()
    t.eq(false, scene_terminal.declares({ name = "logs", blocks = {} }, "logs"))
    t.eq(false, scene_terminal.declares(nil, "logs"))
  end)
end)

t.describe("scene_terminal.class_for", function()
  t.it("names the scene's own terminal", function()
    t.eq("Kitty-code", scene_terminal.class_for("code"))
    t.eq("Kitty-knowledge", scene_terminal.class_for("knowledge"))
  end)
end)
