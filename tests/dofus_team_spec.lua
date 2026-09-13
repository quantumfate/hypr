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

---Grouped-fullscreen carry-along (LEO-243): the window.active guard hands a
---rendered sibling's fullscreen/maximize onto the newly focused member.
---`fullscreen_client` mirrors the gaming tag's style (client fullscreen+max
---whenever an internal mode is active).
---@param members { title: string, fullscreen: integer }[] in group order
---@return HL.Group
local function set_fullscreen_group(members)
  local list = {}
  for _, m in ipairs(members) do
    list[#list + 1] = {
      class = "Dofus.x64",
      title = m.title,
      address = "addr_" .. m.title,
      fullscreen = m.fullscreen,
      fullscreen_client = m.fullscreen ~= 0 and 3 or 0,
    }
  end
  local group = { members = (#list == 1) and list[1] or list }
  for _, w in ipairs(list) do
    w.group = group
  end
  return group
end

---Invoke every window.active handler the stub recorded (team registers one).
---@param w any
local function active_event(w)
  local handlers = hl.event_handlers["window.active"]
  assert(handlers and #handlers > 0, "expected a window.active handler to be registered")
  for _, cb in ipairs(handlers) do
    cb(w)
  end
end

t.describe("dofus.team fullscreen follow-along (LEO-243)", function()
  t.it("registers a window.active handler at require time", function()
    t.ok(hl.event_handlers["window.active"], "expected a window.active handler")
  end)

  t.it("carries a sibling's maximized state onto the focused member (unset old, set new)", function()
    reset()
    local group = set_fullscreen_group({
      { title = "Dofus a", fullscreen = 2 },
      { title = "Dofus b", fullscreen = 0 },
    })
    active_event(group.members[2])

    t.eq(2, #hl.dispatched)
    t.eq("dsp.window.fullscreen_state", hl.dispatched[1].name)
    t.eq("unset", hl.dispatched[1].args[1].action)
    t.eq(0, hl.dispatched[1].args[1].internal)
    t.eq(0, hl.dispatched[1].args[1].client)
    t.eq("address:addr_Dofus a", hl.dispatched[1].args[1].window)

    t.eq("set", hl.dispatched[2].args[1].action)
    t.eq(2, hl.dispatched[2].args[1].internal)
    t.eq(3, hl.dispatched[2].args[1].client)
    t.eq("address:addr_Dofus b", hl.dispatched[2].args[1].window)
  end)

  t.it("carries a plain fullscreen (mode 1) and fullscreen+maximized (mode 3) as-is", function()
    reset()
    local group = set_fullscreen_group({
      { title = "Dofus a", fullscreen = 1 },
      { title = "Dofus b", fullscreen = 0 },
    })
    active_event(group.members[2])

    t.eq(2, #hl.dispatched)
    t.eq("address:addr_Dofus a", hl.dispatched[1].args[1].window)
    t.eq(1, hl.dispatched[2].args[1].internal)
    t.eq(3, hl.dispatched[2].args[1].client)
    t.eq("address:addr_Dofus b", hl.dispatched[2].args[1].window)

    -- Same carry for a both (mode 3) rendered sibling.
    reset()
    group = set_fullscreen_group({
      { title = "Dofus a", fullscreen = 3 },
      { title = "Dofus b", fullscreen = 0 },
    })
    active_event(group.members[2])
    t.eq("address:addr_Dofus a", hl.dispatched[1].args[1].window)
    t.eq(3, hl.dispatched[2].args[1].internal)
    t.eq(3, hl.dispatched[2].args[1].client)
  end)

  t.it("is a no-op when no sibling carries a rendered state", function()
    reset()
    local group = set_fullscreen_group({
      { title = "Dofus a", fullscreen = 0 },
      { title = "Dofus b", fullscreen = 0 },
    })
    active_event(group.members[2])
    t.eq(0, #hl.dispatched)
  end)

  t.it("is a no-op when the focused member is itself the rendered one", function()
    reset()
    local group = set_fullscreen_group({
      { title = "Dofus a", fullscreen = 2 },
      { title = "Dofus b", fullscreen = 0 },
    })
    active_event(group.members[1])
    t.eq(0, #hl.dispatched)
  end)

  t.it("is a no-op in a single-member group (bare HL.Group.members)", function()
    reset()
    local group = set_fullscreen_group({ { title = "Dofus solo", fullscreen = 2 } })
    active_event(group.members)
    t.eq(0, #hl.dispatched)
  end)

  t.it("ignores focus on non-Dofus windows", function()
    reset()
    active_event({ class = "some-other-app", title = "x", group = { members = {} } })
    t.eq(0, #hl.dispatched)
  end)
end)
