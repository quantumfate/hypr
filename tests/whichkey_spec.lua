-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
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
        { key = "o", desc = "Opens", opens = "wk-other" },
      },
    })
    local node = whichkey.node("wk-root-a")
    t.eq("", node.parent, "root has no parent")
    t.eq(3, #node.items, "three entries")
    local group, plain, opens = node.items[1], node.items[2], node.items[3]
    t.eq("g", group.key)
    t.eq("Grouped", group.desc)
    t.ok(group.group, "group flagged")
    t.eq("wk-root-a-g", group.child, "default child name")
    t.eq(false, plain.group, "plain leaf not flagged")
    t.eq("Plain", plain.desc)
    t.eq({ "SHIFT" }, plain.mods, "mods carried")
    t.ok(opens.group, "opens leaf rendered as a group")
    t.eq("wk-other", opens.child, "opens leaf names its destination")
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

t.describe("dumping only what is loaded", function()
  --- A mode withholds whole binding trees, so the cheatsheet must render the
  --- set of keys that work rather than every key that was ever defined. A
  --- filtered list can disagree with what the keys do; a list derived from the
  --- enabled set cannot.
  local function registered()
    package.loaded["hypr.lib.whichkey"] = nil
    local wk = require("hypr.lib.whichkey")
    wk.register("dofus", nil, {})
    wk.register("dofus-team", "dofus", {})
    wk.register("llm", nil, {})
    -- The which-key overlay itself lives in an always-enabled tree; its
    -- leaves reach other trees through `opens`.
    wk.register("flex", nil, {
      { key = "d", desc = "Dofus", opens = "dofus" },
      { key = "t", desc = "Has no destination", action = function() end },
    })
    return wk
  end

  local function dumped(wk, admitted)
    local path = os.tmpname()
    wk.path = path
    wk.dump(admitted)
    local f = assert(io.open(path, "r"))
    local raw = f:read("a")
    f:close()
    os.remove(path)
    return raw
  end

  t.it("keeps everything when nothing narrows it", function()
    local wk = registered()
    local raw = dumped(wk, nil)
    t.ok(raw:match("dofus"), raw)
    t.ok(raw:match("llm"), raw)
  end)

  t.it("omits a tree that is not loaded", function()
    local wk = registered()
    local raw = dumped(wk, { dofus = true })
    t.ok(raw:match("dofus"), raw)
    t.ok(not raw:match("llm"), "a withheld tree was still listed")
  end)

  t.it("keeps a nested submap with the tree it belongs to", function()
    -- Otherwise a mode would have to name every nesting depth to admit one
    -- feature, and the cheatsheet would lose the tree's interior.
    local wk = registered()
    local raw = dumped(wk, { dofus = true })
    t.ok(raw:match("dofus%-team"), "the nested submap was dropped with its parent loaded")
  end)

  t.it("drops a nested submap when its tree is withheld", function()
    local wk = registered()
    local raw = dumped(wk, { llm = true })
    t.ok(not raw:match("dofus"), "a withheld tree's interior was still listed")
  end)

  t.it("drops an opens leaf whose destination tree is withheld", function()
    -- The overlay always answers admitted, so without the leaf-level gate its
    -- Dofus entry would be listed while every bind inside the submap is away.
    local wk = registered()
    local raw = dumped(wk, { llm = true, flex = true })
    t.ok(raw:match("Has no destination"), "a plain leaf of the same tree survives")
    t.ok(not raw:match('"dofus"'), "the door into a withheld tree was still rendered")
  end)

  t.it("restores an opens leaf when its tree is admitted again", function()
    -- The narrow is a copy's, never the registry's: a dump is run on every
    -- mode change, and a drop that ate the entry would lose it forever.
    local wk = registered()
    local withheld = dumped(wk, { llm = true, flex = true })
    local admitted = dumped(wk, { llm = true, flex = true, dofus = true })
    t.ok(not withheld:match('"dofus"'), "the leaf is gone while the tree is withheld")
    t.ok(admitted:match("Dofus"), "the leaf returns when the mode brings the tree back")
  end)
end)

t.describe("boot dump is the admitted set", function()
  t.it("hyprfocus.apply writes a filtered whichkey document", function()
    -- The boot path must not dump the full registry. Applying the active mode
    -- already re-dumps from the loaded set; this pins that contract end-to-end.
    for _, mod in ipairs({
      "hypr.lib.store",
      "hypr.hyprfocus.binds",
      "hypr.hyprfocus.hold",
      "hypr.hyprfocus.workspaces",
      "hypr.hyprfocus.resolve",
      "hypr.hyprfocus.plan",
      "hypr.hyprfocus.init",
      "hypr.lib.whichkey",
    }) do
      package.loaded[mod] = nil
    end

    local stub = require("tests.hl_stub").new()
    _G.hl = stub
    stub.bind = function(key)
      local h = { key = key, enabled = true }
      function h:set_enabled(v)
        self.enabled = v
      end
      return h
    end
    stub.define_submap = function(_, fn)
      fn()
    end

    local declaration = {
      version = 3,
      base = {
        bindings = { "root", "terminal", "dofus" },
        scenes = { code = {} },
      },
      modes = {
        neutral = { name = "Neutral", hidden = true, scenes = { { name = "code", monitor = "primary" } } },
        work = {
          name = "Work",
          scenes = { { name = "code", monitor = "primary" } },
          bindings = { remove = { "dofus" } },
        },
      },
    }
    package.loaded["hypr.lib.store"] = {
      define = function(name)
        local data
        if name == "hyprfocus" then
          data = declaration
        elseif name == "focus" then
          data = { mode = "work" }
        elseif name == "hyprfocus-held" then
          data = {}
        else
          data = {}
        end
        return {
          get = function(_, key)
            return key == nil and data or data[key]
          end,
          set = function(_, patch)
            for k, v in pairs(patch) do
              data[k] = v
            end
          end,
        }
      end,
    }

    local binds = require("hypr.hyprfocus.binds")
    binds.reset()
    binds.bind("+SUPER+t+", function() end, { description = "Test root bind" })
    binds.submap("terminal", function()
      binds.bind("a")
    end)
    binds.submap("dofus", function()
      binds.bind("b")
    end)

    local workspaces = require("hypr.hyprfocus.workspaces")
    workspaces.reset()
    local rule = hl.workspace_rule({ workspace = "code", default_name = "code" })
    workspaces.record("code", rule)

    local wk = require("hypr.lib.whichkey")
    wk.register("terminal", nil, { { key = "t", desc = "Terminal" } })
    wk.register("dofus", nil, { { key = "d", desc = "Dofus" } })

    local hyprfocus = require("hypr.hyprfocus.init")
    local path = os.tmpname()
    wk.path = path
    local report = hyprfocus.apply("work")
    t.ok(report, tostring(report))

    local f = assert(io.open(path, "r"))
    local raw = f:read("a")
    f:close()
    os.remove(path)
    t.ok(raw:match("terminal"), raw)
    t.ok(raw:match("Test root bind"), "boot dump dropped the root/reset node")
    t.ok(not raw:match("dofus"), "boot dump contained a withheld tree")
  end)
end)
