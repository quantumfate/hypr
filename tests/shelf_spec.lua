-- Test fixtures stub the runtime: partial `hl` objects the type system cannot prove.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field
--- Shelves: the launch-or-toggle decision, per-shelf admission by tree, and
--- the window rules that land each app on its shelf.
local t = require("tests.harness")

local SIGNAL = { name = "signal", key = "s", class = "signal", cmd = "signal-desktop", desc = "Signal" }
local STEAM = { name = "steam", key = "t", class = "steam", cmd = "steam", desc = "Steam", tree = "shelf-steam" }
local ANKAMA = {
  name = "ankama",
  key = "a",
  class = "Ankama Launcher",
  cmd = ",ankama-launcher.sh",
  desc = "Ankama Launcher",
  tree = "shelf-ankama",
  scene = "dofus",
}

-- A ctx as the shelf submap entry builds it: the active desk's placements,
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

t.describe("shelf decisions", function()
  local shelf = require("hypr.lib.shelf")

  t.it("launches an app that is not running, without toggling an empty shelf", function()
    local d = shelf.decide(SIGNAL, { { class = "vesktop" } })
    t.eq("signal-desktop", d.launch)
    t.eq(nil, d.toggle)
  end)

  t.it("toggles the shelf of a running app wherever its window is", function()
    local d = shelf.decide(SIGNAL, { { class = "signal", workspace = { name = "special:shelf-signal" } } })
    t.eq(nil, d.launch)
    t.eq("shelf-signal", d.toggle)
  end)

  t.it("sends each app to its own floating shelf, silently (LEO-372)", function()
    local stub = require("tests.hl_stub").new()
    _G.hl = stub
    shelf.rules({ SIGNAL, STEAM })
    t.eq(2, #stub.window_rules)
    t.eq("special:shelf-steam silent", stub.window_rules[2].workspace)
    t.eq(true, stub.window_rules[2].float)
  end)

  t.it("a global shelf never asks to focus anything, even with a ctx", function()
    local d = shelf.decide(SIGNAL, {}, ctx({ { name = "dofus", monitor = "game" } }, { { name = "game" } }))
    t.eq(nil, d.focus)
    t.eq(nil, d.reason)
  end)

  t.it("an owned shelf focuses its owner scene when another workspace is active there", function()
    local d = shelf.decide(
      ANKAMA,
      {},
      ctx({ { name = "dofus", monitor = "game" } }, { { name = "game", activeWorkspace = { name = "code" } } })
    )
    t.eq("name:dofus", d.focus)
    t.ok(d.monitor ~= nil, "an owned shelf always focuses its owner's monitor first")
  end)

  t.it("an owned shelf does not focus when its owner scene is already active there", function()
    local d = shelf.decide(
      ANKAMA,
      {},
      ctx({ { name = "dofus", monitor = "game" } }, { { name = "game", activeWorkspace = { name = "dofus" } } })
    )
    t.eq(nil, d.focus)
  end)

  t.it("an owned shelf whose owner scene is not in the active desk opens on the focused monitor", function()
    local d = shelf.decide(ANKAMA, {}, ctx({ { name = "code", monitor = "main" } }, { { name = "main" } }))
    t.eq(nil, d.focus)
    t.ok(d.reason and d.reason:match("not in the active mode's desk"), "explains the fallback")
  end)

  t.it("an owned shelf with no ctx at all never focuses, same as no active desk", function()
    local d = shelf.decide(ANKAMA, {})
    t.eq(nil, d.focus)
    t.ok(d.reason, "still reports why it fell back, for the caller to log")
  end)
end)

t.describe("shelf pending launch (LEO-372: silent rule, key press still shows it)", function()
  local shelf = require("hypr.lib.shelf")

  t.it("pending_for answers only for a class with a pending entry", function()
    t.eq(SIGNAL, shelf.pending_for({ SIGNAL, STEAM }, { signal = SIGNAL }, "signal"))
    t.eq(nil, shelf.pending_for({ SIGNAL, STEAM }, { signal = SIGNAL }, "steam"))
    t.eq(nil, shelf.pending_for({ SIGNAL, STEAM }, {}, "signal"))
  end)

  t.it("show_decision toggles a global shelf that is not already showing", function()
    local d = shelf.show_decision(SIGNAL, { monitors = {} })
    t.eq("shelf-signal", d.toggle)
    t.eq(nil, d.monitor)
  end)

  t.it("show_decision does not toggle a shelf already showing on any monitor", function()
    local d = shelf.show_decision(
      SIGNAL,
      { monitors = { { name = "main", specialWorkspace = { name = "special:shelf-signal" } } } }
    )
    t.eq(nil, d.toggle)
  end)

  t.it("show_decision focuses an owned shelf's monitor first, like decide", function()
    local d = shelf.show_decision(ANKAMA, {
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

  t.it("show_decision does not toggle an owned shelf already showing on its monitor", function()
    local d = shelf.show_decision(ANKAMA, {
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

t.describe("shelf exemption from hold", function()
  local shelf = require("hypr.lib.shelf")

  t.it("a window on any shelf special workspace is exempt", function()
    t.ok(shelf.exempt({ workspace = { name = "special:shelf-ankama" } }, {}))
  end)

  t.it("a window of a configured shelf's class is exempt, wherever it stands", function()
    t.ok(shelf.exempt({ class = "steam", workspace = { name = "code" } }, { STEAM }))
  end)

  t.it("an unrelated window on an unrelated workspace is not exempt", function()
    t.eq(false, shelf.exempt({ class = "kitty", workspace = { name = "code" } }, { STEAM }))
  end)
end)

t.describe("shelf admission", function()
  t.it("a shelf with a tree is withheld on its own; the rest of the submap stays", function()
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
    for _, mod in ipairs({ "hypr.hyprfocus.binds", "hypr.lib.submap", "hypr.lib.whichkey", "hypr.lib.shelf" }) do
      package.loaded[mod] = nil
    end
    local binds = require("hypr.hyprfocus.binds")
    local shelf = require("hypr.lib.shelf")
    require("hypr.lib.submap").tree({
      name = "shelf",
      desc = "Shelves",
      entries = { shelf.entry(SIGNAL), shelf.entry(STEAM) },
    })
    t.eq(1, binds.size("shelf-steam"), "the steam key answers to its own tree")
    t.eq(0, #binds.admit({}))
    t.eq("shelf-steam", table.concat(binds.admit({ "shelf-steam" }), ","))
    t.ok(binds.size("shelf") > 0, "signal stays in the shelf tree")
  end)
end)
