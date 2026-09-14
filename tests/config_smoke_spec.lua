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

  t.it("registers binds and workspace rules", function()
    -- A config that loads but registers nothing is the same desk as one that
    -- raised, so loading is not on its own the thing worth asserting.
    load_config("quantum-desktop")
    t.ok(#hl.binds > 10, "expected the bind tree to be built")
    t.ok(#hl.workspace_rules > 0, "expected workspace rules")
    t.ok(hl.layouts and hl.layouts.scene, "expected the scene layout to register")
  end)
end)
