-- Test fixtures stub the runtime: partial `hl` objects the type system cannot prove.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field
--- Shelves: the launch-or-toggle decision, per-shelf admission by tree, and
--- the window rules that land each app on its shelf.
local t = require("tests.harness")

local SIGNAL = { name = "signal", key = "s", class = "signal", cmd = "signal-desktop", desc = "Signal" }
local STEAM = { name = "steam", key = "t", class = "steam", cmd = "steam", desc = "Steam", tree = "shelf-steam" }

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

  t.it("sends each app to its own floating shelf", function()
    local stub = require("tests.hl_stub").new()
    _G.hl = stub
    shelf.rules({ SIGNAL, STEAM })
    t.eq(2, #stub.window_rules)
    t.eq("special:shelf-steam", stub.window_rules[2].workspace)
    t.eq(true, stub.window_rules[2].float)
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
