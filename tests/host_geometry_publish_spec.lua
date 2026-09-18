-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- LEO-340: conf/host.lua's build() publishes each monitor's base left/right
--- outer gap to the `geometry` store, for the quickshell bar to mirror as its
--- side inset. Sandboxed QF_STORE (a tempdir): never the real store.
local t = require("tests.harness")

local dir = t.tempdir()
local real_getenv = os.getenv
os.getenv = function(k)
  if k == "QF_STORE" then
    return dir
  end
  if k == "XDG_STATE_HOME" then
    return dir .. "/legacy"
  end
  return real_getenv(k)
end

---Runs conf/host.lua's build() for one host/monitor fingerprint, through the
---stub, and returns the published `geometry` store's `monitors` table.
---@param hostname string
---@param monitors HL.Monitor[]
---@return table<string, {left: integer, right: integer}>
local function published_monitors(hostname, monitors)
  for name in pairs(package.loaded) do
    if name == "hypr" or name:match("^hypr%.") or name:match("^conf%.") then
      package.loaded[name] = nil
    end
  end

  _G.hl = require("tests.hl_stub").new()
  hl.monitors = monitors
  hl.config_values["general.gaps_out"] = { top = 8, right = 40, bottom = 40, left = 40 }

  local util = require("hypr.lib.util")
  local real_hostname = util.hostname
  util.hostname = function()
    return hostname
  end

  require("conf.host").build()
  util.hostname = real_hostname

  local Store = require("hypr.lib.store")
  return Store.define("geometry"):get("monitors")
end

t.describe("conf.host.build publishes per-monitor gaps -- LEO-340", function()
  t.it("desk-dual: primary takes the profile's 80px gap, secondary the profile's 64px", function()
    local monitors = published_monitors("quantum-desktop", { { width = 5120 }, { width = 1920 } })
    t.eq({ left = 80, right = 80 }, monitors["DP-1"])
    t.eq({ left = 64, right = 64 }, monitors["DP-2"])
  end)

  t.it("laptop-solo: both monitors take the profile's 48px gap", function()
    local monitors = published_monitors("quantum-laptop", { { width = 1920 } })
    t.eq({ left = 48, right = 48 }, monitors["eDP-1"])
    t.eq({ left = 48, right = 48 }, monitors["HDMI-A-1"])
  end)

  t.it("never publishes the solo widen: the store holds only the base gap", function()
    local monitors = published_monitors("quantum-desktop", { { width = 5120 }, { width = 1920 } })
    t.ok(monitors["DP-1"].left < 180, "published gap looks widened by SOLO_EXTRA")
  end)
end)
