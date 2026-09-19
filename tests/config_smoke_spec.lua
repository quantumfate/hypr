-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- The whole config, loaded.
---
--- The failure this exists for is not subtle and has cost three sessions: a
--- module-level error anywhere in the tree raises at config load, and every
--- module required after it never runs — so the desk comes up with no
--- keybinds and no workspace rules. Assigning to the read-only `hl` table did
--- it once; a keybind Hyprland could not parse did it twice.
---
--- Every other spec loads one module. This loads what Hyprland loads, through
--- the stub, for both hosts.
local t = require("tests.harness")

---Load the real hyprland.lua for a named host, with the runtime stubbed.
---@param hostname string
---@return boolean, string?
local function load_config(hostname)
  for name in pairs(package.loaded) do
    if name == "hypr" or name:match("^hypr%.") then
      package.loaded[name] = nil
    end
  end
  -- Read-only, as the runtime is: a module assigning to `hl` must fail here
  -- rather than on the desk.
  _G.hl = require("tests.hl_stub").new({ readonly = true })
  _G.config = nil

  -- hyprland.lua picks its host by shelling out to `hostname`; the stub cannot
  -- change the machine's name, so the lookup is redirected instead.
  package.loaded["hypr.lib.util"] = nil
  local util = require("hypr.lib.util")
  local real = util.hostname
  util.hostname = function()
    return hostname
  end

  local ok, err = pcall(dofile, "hyprland.lua")
  util.hostname = real
  return ok, err and tostring(err) or nil
end

t.describe("the config loads", function()
  for _, host in ipairs({ "quantum-desktop", "quantum-laptop" }) do
    t.it("on " .. host, function()
      local ok, err = load_config(host)
      t.ok(ok, "config failed to load: " .. tostring(err))
    end)
  end

  t.it("a host with no file of its own takes the default desk", function()
    local ok, err = load_config("quantum-nowhere")
    t.ok(ok, "fallback host failed to load: " .. tostring(err))
    t.eq("eDP-1", config.host.primary_monitor)
    t.ok(config.host.workspaces.workspace_specs[1].persistent, "spec defaults filled for the fallback anytime")
    t.eq("scene", config.host.workspaces.workspace_specs[1].layout)

    local ok2, err2 = load_config("quantum-desktop")
    t.ok(ok2, "config failed to load after the fallback: " .. tostring(err2))
    -- Workspace 1 is quantum-desktop's "code" scene, on the deck layout.
    t.eq("lua:deck", hl.workspace_rules[1].layout)
  end)

  t.it("registers binds and workspace rules", function()
    -- A config that loads but registers nothing is the same desk as one that
    -- raised, so loading is not on its own the thing worth asserting.
    load_config("quantum-desktop")
    t.ok(#hl.binds > 10, "expected the bind tree to be built")
    t.ok(#hl.workspace_rules > 0, "expected workspace rules")
    t.ok(hl.layouts and hl.layouts.scene, "expected the scene layout to register")
    t.ok(hl.layouts and hl.layouts.deck, "expected the deck layout to register")

    -- A named workspace keys its rule on the name, or any auto-named duplicate
    -- created while the id-backed workspace is withdrawn inherits no rule.
    local named = {}
    for _, rule in ipairs(hl.workspace_rules) do
      if rule.default_name then
        named[rule.default_name] = rule
      end
    end
    t.eq("name:code", named.code.workspace, "workspace 1 must key its rule on default_name")
    t.eq("lua:deck", named.code.layout, "workspace 1 is the desktop's deck-layout scene")
  end)
end)
