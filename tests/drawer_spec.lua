-- Test fixtures stub the runtime: partial `hl` objects the type system cannot prove.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field
--- Drawers (docs/shelves.md, "shelf" in the UI): the launch-or-toggle
--- decision, per-drawer admission by synthetic tree, and the window rules
--- that land each app on its shelf.
local t = require("tests.harness")

local SIGNAL = { id = "signal", key = "s", class = "signal", launch = "signal-desktop", desc = "Signal", scenes = {} }
local STEAM = {
  id = "steam",
  key = "t",
  class = "steam",
  launch = "steam",
  desc = "Steam",
  scenes = { "steam-games" },
  tree = "drawer:steam",
}
local ANKAMA = {
  id = "ankama",
  key = "a",
  class = "Ankama Launcher",
  launch = ",ankama-launcher.sh",
  desc = "Ankama Launcher",
  scenes = { "dofus" },
  tree = "drawer:ankama",
}

-- A ctx as the drawer submap entry builds it: the active desk's placements,
-- `hyprfocus.output_for` (role -> output), and `hl.get_monitors()`.
local function ctx(scenes, monitors)
  return {
    desk = { scenes = scenes },
    output_for = function(role)
      return role
    end,
    monitors = monitors,
  }
end

t.describe("drawer decisions", function()
  local drawer = require("hypr.lib.drawer")

  t.it("launches an app that is not running, without toggling an empty drawer", function()
    local d = drawer.decide(SIGNAL, { { class = "vesktop" } })
    t.eq("signal-desktop", d.launch)
    t.eq(nil, d.toggle)
  end)

  t.it("never opens a drawer on an ignored focused monitor", function()
    local c = { focused = "HDMI-A-1", primary = "DP-1", ignored = { "HDMI-A-1" }, monitors = {} }
    t.eq("DP-1", drawer.decide(SIGNAL, {}, c).monitor)
    t.eq("DP-1", drawer.show_decision(SIGNAL, c).monitor)
    c.focused = "DP-2"
    t.eq(nil, drawer.decide(SIGNAL, {}, c).monitor)
  end)

  t.it("toggles the shelf of a running app wherever its window is", function()
    local d = drawer.decide(SIGNAL, { { class = "signal", workspace = { name = "special:shelf-signal" } } })
    t.eq(nil, d.launch)
    t.eq("shelf-signal", d.toggle)
  end)

  t.it("sends each app to its own floating shelf, silently (LEO-372)", function()
    local stub = require("tests.hl_stub").new()
    _G.hl = stub
    drawer.rules({ SIGNAL, STEAM })
    t.eq(2, #stub.window_rules)
    t.eq("special:shelf-steam silent", stub.window_rules[2].workspace)
    t.eq(true, stub.window_rules[2].float)
  end)

  t.it("a global drawer never asks to focus anything, even with a ctx", function()
    local d = drawer.decide(SIGNAL, {}, ctx({ { name = "dofus", monitor = "game" } }, { { name = "game" } }))
    t.eq(nil, d.focus)
    t.eq(nil, d.reason)
  end)

  t.it("an owned drawer focuses its owner scene when another workspace is active there", function()
    local d = drawer.decide(
      ANKAMA,
      {},
      ctx({ { name = "dofus", monitor = "game" } }, { { name = "game", activeWorkspace = { name = "code" } } })
    )
    t.eq("name:dofus", d.focus)
    t.ok(d.monitor ~= nil, "an owned drawer always focuses its owner's monitor first")
  end)

  t.it("an owned drawer does not focus when its owner scene is already active there", function()
    local d = drawer.decide(
      ANKAMA,
      {},
      ctx({ { name = "dofus", monitor = "game" } }, { { name = "game", activeWorkspace = { name = "dofus" } } })
    )
    t.eq(nil, d.focus)
  end)

  t.it("an owned drawer whose owner scene is not in the active desk opens on the focused monitor", function()
    local d = drawer.decide(ANKAMA, {}, ctx({ { name = "code", monitor = "main" } }, { { name = "main" } }))
    t.eq(nil, d.focus)
    t.ok(d.reason and d.reason:match("not in the active mode's desk"), "explains the fallback")
  end)

  t.it("an owned drawer with no ctx at all never focuses, same as no active desk", function()
    local d = drawer.decide(ANKAMA, {})
    t.eq(nil, d.focus)
    t.ok(d.reason, "still reports why it fell back, for the caller to log")
  end)

  t.it("a press while the launch is pending neither re-launches nor toggles", function()
    local d = drawer.decide(ANKAMA, {}, ctx({ { name = "dofus", monitor = "game" } }, { { name = "game" } }), true)
    t.eq(nil, d.launch)
    t.eq(nil, d.toggle)
    t.eq(nil, d.monitor)
    t.eq(nil, d.focus)
  end)

  t.it("pending wins even once the window has landed and is running", function()
    local d = drawer.decide(SIGNAL, { { class = "signal" } }, nil, true)
    t.eq(nil, d.launch)
    t.eq(nil, d.toggle)
  end)
end)

t.describe("drawer pending launch (LEO-372: silent rule, key press still shows it)", function()
  local drawer = require("hypr.lib.drawer")

  t.it("pending_for answers only for a class with a pending entry", function()
    t.eq(SIGNAL, drawer.pending_for({ SIGNAL, STEAM }, { signal = SIGNAL }, "signal"))
    t.eq(nil, drawer.pending_for({ SIGNAL, STEAM }, { signal = SIGNAL }, "steam"))
    t.eq(nil, drawer.pending_for({ SIGNAL, STEAM }, {}, "signal"))
  end)

  t.it("show_decision toggles a global drawer that is not already showing", function()
    local d = drawer.show_decision(SIGNAL, { monitors = {} })
    t.eq("shelf-signal", d.toggle)
    t.eq(nil, d.monitor)
  end)

  t.it("show_decision does not toggle a drawer already showing on any monitor", function()
    local d = drawer.show_decision(
      SIGNAL,
      { monitors = { { name = "main", specialWorkspace = { name = "special:shelf-signal" } } } }
    )
    t.eq(nil, d.toggle)
  end)

  t.it("show_decision focuses an owned drawer's monitor first, like decide", function()
    local d = drawer.show_decision(ANKAMA, {
      desk = { scenes = { { name = "dofus", monitor = "game" } } },
      output_for = function(role)
        return role
      end,
      monitors = { { name = "game", activeWorkspace = { name = "code" } } },
    })
    t.eq("game", d.monitor)
    t.eq("name:dofus", d.focus)
    t.eq("shelf-ankama", d.toggle)
  end)

  t.it("show_decision does not toggle an owned drawer already showing on its monitor", function()
    local d = drawer.show_decision(ANKAMA, {
      desk = { scenes = { { name = "dofus", monitor = "game" } } },
      output_for = function(role)
        return role
      end,
      monitors = {
        { name = "game", activeWorkspace = { name = "dofus" }, specialWorkspace = { name = "special:shelf-ankama" } },
      },
    })
    t.eq(nil, d.toggle)
  end)
end)

t.describe("drawer exemption from hold", function()
  local drawer = require("hypr.lib.drawer")

  t.it("a window on any shelf special workspace is exempt", function()
    t.ok(drawer.exempt({ workspace = { name = "special:shelf-ankama" } }, {}))
  end)

  t.it("a window of a configured drawer's class is exempt, wherever it stands", function()
    t.ok(drawer.exempt({ class = "steam", workspace = { name = "code" } }, { STEAM }))
  end)

  t.it("an unrelated window on an unrelated workspace is not exempt", function()
    t.eq(false, drawer.exempt({ class = "kitty", workspace = { name = "code" } }, { STEAM }))
  end)
end)

t.describe("drawer admission", function()
  t.it("a drawer with a tree is withheld on its own; the rest of the submap stays", function()
    local stub = require("tests.hl_stub").new()
    _G.hl = stub
    -- The stub records but returns nothing; give binds a real handle.
    stub.bind = function(key)
      local handle = { key = key }
      function handle:set_enabled(value)
        self.enabled = value
      end
      return handle
    end
    for _, mod in ipairs({ "hypr.hyprfocus.binds", "hypr.lib.submap", "hypr.lib.whichkey", "hypr.lib.drawer" }) do
      package.loaded[mod] = nil
    end
    local binds = require("hypr.hyprfocus.binds")
    local drawer = require("hypr.lib.drawer")
    require("hypr.lib.submap").tree({
      name = "shelf",
      desc = "Shelves",
      entries = { drawer.entry(SIGNAL), drawer.entry(STEAM) },
    })
    t.eq(1, binds.size("drawer:steam"), "the steam key answers to its own tree")
    t.eq(0, #binds.admit({}))
    t.eq("drawer:steam", table.concat(binds.admit({ "drawer:steam" }), ","))
    t.ok(binds.size("shelf") > 0, "signal stays in the shelf tree")
  end)
end)
