-- Project-bindings resolution (LEO-311 chunk D): hypr/lib/project.lua is
-- pure, so this drives it with plain tables instead of a live compositor.
local t = require("tests.harness")
local project = require("hypr.lib.project")

t.describe("project.class_for / project_name_from_class", function()
  t.it("round-trips a plain name", function()
    t.eq("Proj-hypr", project.class_for("hypr"))
    t.eq("hypr", project.project_name_from_class("Proj-hypr"))
  end)

  t.it("sanitizes the same way ,proj.sh's class_for does", function()
    t.eq("Proj-my_repo", project.class_for("my repo"))
  end)

  t.it("returns nil for a non-project class", function()
    t.eq(nil, project.project_name_from_class("Kitty-Main"))
    t.eq(nil, project.project_name_from_class(nil))
  end)
end)

t.describe("project.focused_class", function()
  t.it("returns the class when a project window is focused", function()
    t.eq("Proj-hypr", project.focused_class({ class = "Proj-hypr" }))
  end)

  t.it("returns nil for a non-project window or no window", function()
    t.eq(nil, project.focused_class({ class = "kitty" }))
    t.eq(nil, project.focused_class(nil))
  end)
end)

t.describe("project.slot_address", function()
  local windows = {
    { class = "Proj-a", address = "0x1", tags = { "slot:nvim" } },
    { class = "Proj-a", address = "0x2", tags = { "slot:run" } },
    { class = "Proj-b", address = "0x3", tags = { "slot:nvim" } },
  }

  t.it("finds the tagged window of the given class", function()
    t.eq("0x1", project.slot_address(windows, "Proj-a", "nvim"))
    t.eq("0x2", project.slot_address(windows, "Proj-a", "run"))
  end)

  t.it("never crosses into another project's same-role window", function()
    t.eq("0x3", project.slot_address(windows, "Proj-b", "nvim"))
    t.ok(project.slot_address(windows, "Proj-a", "nvim") ~= project.slot_address(windows, "Proj-b", "nvim"))
  end)

  t.it("returns nil when the role isn't live", function()
    t.eq(nil, project.slot_address(windows, "Proj-a", "test"))
    t.eq(nil, project.slot_address({}, "Proj-a", "nvim"))
  end)
end)
