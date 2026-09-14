--- Specs for the which-key registry (hypr.lib.whichkey, LEO-222): submap.lua
--- records every tree node as it builds it, init.lua dumps the registry to
--- $XDG_STATE_HOME/whichkey.json, and a leaf action dismisses the overlay
--- before the submap reset lands (so the overlay starts fading ahead of the
--- base map being live again).
local t = require("tests.harness")

local submap = require("hypr.lib.submap")
local whichkey = require("hypr.lib.whichkey")
local json = require("hypr.lib.json")

---@param key string
---@param submapName string
---@return fun()|nil the bind action for key inside submap
local function action_for(key, submapName)
  for _, b in ipairs(hl.binds) do
    if b.submap == submapName and b.key == key then
      return b.action
    end
  end
  return nil
end

---@param name string
---@return table|nil
local function dispatched_submap(name)
  local last = hl.dispatched[#hl.dispatched]
  if last and last.name == "dsp.submap" and last.args[1] == name then
    return last
  end
  return nil
end

t.describe("whichkey registry (LEO-222)", function()
  t.it("records the tree roots with sanitized items", function()
    submap.tree({
      mods = { "SUPER", "s" },
      name = "wk-root-a",
      desc = "Root",
      entries = {
        { key = "g", desc = "Grouped", entries = { { key = "l", desc = "Leaf", action = function() end } } },
        { key = "e", mods = { "SHIFT" }, desc = "Plain", action = function() end },
      },
    })
    local node = whichkey.node("wk-root-a")
    t.eq("", node.parent, "root has no parent")
    t.eq(2, #node.items, "two entries")
    local group, plain = node.items[1], node.items[2]
    t.eq("g", group.key)
    t.eq("Grouped", group.desc)
    t.ok(group.group, "group flagged")
    t.eq("wk-root-a-g", group.child, "default child name")
    t.eq(false, plain.group, "leaf not flagged")
    t.eq("Plain", plain.desc)
    t.eq({ "SHIFT" }, plain.mods, "mods carried")
  end)

  t.it("records nested children with their parent", function()
    submap.tree({
      mods = { "SUPER", "p" },
      name = "wk-root-b",
      entries = {
        { key = "x", name = "explicit", desc = "Explicitly named", entries = {} },
        { key = "y", entries = {} },
      },
    })
    local explicit = whichkey.node("explicit")
    t.eq("wk-root-b", explicit.parent, "parent threaded")
    t.eq("explicit", whichkey.node("wk-root-b").items[1].child, "explicit name wins")
    t.eq("Explicitly named", whichkey.node("wk-root-b").items[1].desc, "provided desc kept")
    t.eq("wk-root-b-y", whichkey.node("wk-root-b").items[2].child, "default name for anonymous group")
    t.eq("wk-root-b-y", whichkey.node("wk-root-b").items[2].desc, "anonymous group falls back to child name")
  end)

  t.it("dumps a JSON round-trip of the registry", function()
    t.ok(whichkey.node("wk-root-a"), "registry populated")
    local tmp = os.tmpname()
    os.remove(tmp)
    local old = whichkey.path
    whichkey.path = tmp
    whichkey.dump()
    whichkey.path = old
    local f = assert(io.open(tmp, "r"))
    local raw = f:read("*a")
    f:close()
    os.remove(tmp)
    t.ok(raw:find("wk-root-a", 1, true) ~= nil, "---")
    local decoded = assert(json.decode(raw))
    t.ok(decoded["wk-root-b"].items[1].child == "explicit", "nested child serialized")
    t.eq("SHIFT", decoded["wk-root-a"].items[2].mods[1], "mods serialized")
  end)
end)

t.describe("whichkey dismiss on submap exit (LEO-222)", function()
  -- submap.lua's stack is module-level and shared across tests; normalize it
  -- so each test sees a clean tree.
  t.it("leaf action dismisses the overlay before the reset dispatch", function()
    submap.reset()
    submap.tree({
      mods = { "SUPER", "a" },
      name = "wk-dismiss",
      entries = { { key = "l", desc = "Leaf", action = function() end } },
    })
    submap.enter("wk-dismiss")
    local action = action_for("+l+", "wk-dismiss")
    t.ok(action, "leaf bound")
    action()
    t.ok(dispatched_submap(""), "tree exited to the stub base submap")
    local cmd = hl.exec_cmds[#hl.exec_cmds]
    t.ok(cmd and cmd:find("whichkey dismiss", 1, true) ~= nil, "dismiss raised")
  end)

  t.it("a stay leaf keeps the tree open and sends no dismiss", function()
    submap.reset()
    submap.tree({
      mods = { "SUPER", "b" },
      name = "wk-stay",
      entries = { { key = "k", desc = "Stay", stay = true, action = function() end } },
    })
    submap.enter("wk-stay")
    local execs_before = #hl.exec_cmds
    local dispatch_before = #hl.dispatched
    action_for("+k+", "wk-stay")()
    t.eq(execs_before, #hl.exec_cmds, "no dismiss for a stay action")
    t.eq(dispatch_before, #hl.dispatched, "stay leaf dispatches nothing further")
  end)

  t.it("escape back to the base dismisses when the stack empties", function()
    submap.reset()
    submap.tree({
      mods = { "SUPER", "c" },
      name = "wk-back",
      entries = {},
    })
    submap.enter("wk-back")
    submap.back()
    t.ok(dispatched_submap(""), "popped to the stub base submap")
    local cmd = hl.exec_cmds[#hl.exec_cmds]
    t.ok(cmd and cmd:find("whichkey dismiss", 1, true) ~= nil, "dismiss raised on pop to base")
  end)
end)
