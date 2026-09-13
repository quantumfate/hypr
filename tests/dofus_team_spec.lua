--- Group-membership addressing for the Dofus roster (LEO-230): iterate/nav
--- cycle the Hyprland group natively, and activate/press read membership off
--- any client's `.group` rather than a standalone window list.
local t = require("tests.harness")
local team = require("hypr.services.dofus.team")

---@param titles string[]
---@param active_title string focused window's title (used by on_dofus/press)
local function set_dofus_group(titles, active_title)
  local members = {}
  for _, title in ipairs(titles) do
    members[#members + 1] = { class = "Dofus.x64", title = title }
  end
  -- HL.Group.members is a bare HL.Window when there is exactly one member,
  -- an array otherwise — mirror that quirk here so the code under test has to
  -- handle it.
  local group = { members = (#members == 1) and members[1] or members }
  -- Every member's `.group` reaches the same group table, same as real
  -- Hyprland (dofus_group() reads it off whichever member get_windows hands
  -- back first).
  for _, w in ipairs(members) do
    w.group = group
  end

  function hl.get_windows(filter)
    if filter and filter.class == "Dofus.x64" then
      return members
    end
    return {}
  end

  function hl.get_active_window()
    return { class = "Dofus.x64", title = active_title, group = group }
  end
end

---Each `it()` reuses the shared stub `hl`, so clear what the previous case
---recorded before running the next.
local function reset()
  hl.dispatched = {}
  hl.exec_cmds = {}
end

t.describe("dofus.team", function()
  t.it("iterate() dispatches a native group cycle, not a window list", function()
    reset()
    set_dofus_group({ "Dofus a", "Dofus b" }, "Dofus a")
    team.iterate({}, false)
    t.eq("dsp.group.next", hl.dispatched[1].name)

    hl.dispatched = {}
    team.iterate({}, true)
    t.eq("dsp.group.prev", hl.dispatched[1].name)
  end)

  t.it("iterate() is a no-op off a Dofus window", function()
    reset()
    function hl.get_active_window()
      return { class = "some-other-app", title = "x" }
    end
    team.iterate({}, false)
    t.eq(0, #hl.dispatched)
  end)

  t.it("nav() reports handled and cycles the group while on Dofus", function()
    reset()
    set_dofus_group({ "Dofus a", "Dofus b" }, "Dofus b")
    local handled = team.nav(false)
    t.ok(handled)
    t.eq("dsp.group.next", hl.dispatched[1].name)
  end)

  t.it("nav() falls through (returns false) off a Dofus window", function()
    reset()
    function hl.get_active_window()
      return { class = "some-other-app", title = "x" }
    end
    t.eq(false, team.nav(false))
    t.eq(0, #hl.dispatched)
  end)

  t.it("activate() maps a 1-based team position onto the PRESENT group members densely", function()
    reset()
    -- Only "b" and "d" are actually open; F1/F2 (i=1,2) should still hit them.
    set_dofus_group({ "Dofus b", "Dofus d" }, "Dofus b")
    team.activate({ "a", "b", "c", "d" }, 1)
    t.eq("dsp.focus", hl.dispatched[1].name)
    t.eq("title:Dofus b", hl.dispatched[1].args[1].window)

    hl.dispatched = {}
    team.activate({ "a", "b", "c", "d" }, 2)
    t.eq("title:Dofus d", hl.dispatched[1].args[1].window)
  end)

  t.it("activate() does nothing for a team slot with no open window", function()
    reset()
    set_dofus_group({ "Dofus b" }, "Dofus b")
    team.activate({ "a", "b" }, 2)
    t.eq(0, #hl.dispatched)
  end)

  t.it("activate() handles a single-member group (HL.Group.members as a bare window)", function()
    reset()
    set_dofus_group({ "Dofus solo" }, "Dofus solo")
    team.activate({ "solo" }, 1)
    t.eq("title:Dofus solo", hl.dispatched[1].args[1].window)
  end)

  t.it("press() restores the pre-iteration active window afterwards (LEO-129)", function()
    reset()
    -- Active window ("a") differs from `main` (defaults to the last team
    -- member, "b"), so the macro's final focus target is unambiguous.
    set_dofus_group({ "Dofus a", "Dofus b" }, "Dofus a")
    team.press({ "a", "b" })

    local cmd = hl.exec_cmds[#hl.exec_cmds]
    local main_pos = cmd:find("title:Dofus b", 1, true)
    local restore_pos = cmd:find("title:Dofus a", main_pos, true)
    t.ok(main_pos, "expected a focus on `main` (Dofus b)")
    t.ok(restore_pos, "expected a focus on the pre-press active window (Dofus a) after `main`")
  end)

  t.it("press() is a no-op off a Dofus window", function()
    reset()
    function hl.get_active_window()
      return { class = "some-other-app", title = "x" }
    end
    team.press({ "a", "b" })
    t.eq(0, #hl.exec_cmds)
  end)
end)
