-- LEO-368: conf/host.lua's build() publishes the primary/secondary role ->
-- output map to the `geometry` store, next to the gaps LEO-340 already
-- writes, so the shell can read a monitor's role instead of guessing it from
-- the gaps map's key order. Sandboxed QF_STORE (a tempdir): never the real
-- store.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
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
---stub, and returns the published `geometry` store's `roles` table.
---@param hostname string
---@param monitors HL.Monitor[]
---@return table<string, string>
local function published_roles(hostname, monitors)
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
  return Store.define("geometry"):get("roles")
end

---Runs build(), then fires `event` with `hl.get_monitors()` already swapped
---to `monitors_after`, mimicking outputs enumerating after config load
---(hit on every nested e2e boot) or a hotplug. Returns the republished
---`roles` table.
---@param hostname string
---@param monitors_before HL.Monitor[]
---@param event "monitor.added"|"monitor.removed"
---@param monitors_after HL.Monitor[]
---@return table<string, string>
local function roles_after_event(hostname, monitors_before, event, monitors_after)
  for name in pairs(package.loaded) do
    if name == "hypr" or name:match("^hypr%.") or name:match("^conf%.") then
      package.loaded[name] = nil
    end
  end

  _G.hl = require("tests.hl_stub").new()
  hl.monitors = monitors_before
  hl.config_values["general.gaps_out"] = { top = 8, right = 40, bottom = 40, left = 40 }

  local util = require("hypr.lib.util")
  local real_hostname = util.hostname
  util.hostname = function()
    return hostname
  end

  require("conf.host").build()
  util.hostname = real_hostname

  hl.monitors = monitors_after
  for _, cb in ipairs(hl.event_handlers[event] or {}) do
    cb()
  end

  local Store = require("hypr.lib.store")
  return Store.define("geometry"):get("roles")
end

t.describe("conf.host.build re-publishes the role map on monitor.added/removed -- LEO-368", function()
  t.it("monitor.added fills in a role missing at boot (the e2e/cold-boot race)", function()
    local roles = roles_after_event(
      "quantum-desktop",
      { { name = "DP-1", width = 5120 } }, -- DP-2 not enumerated yet at build()
      "monitor.added",
      { { name = "DP-1", width = 5120 }, { name = "DP-2", width = 1920 } }
    )
    t.eq({ primary = "DP-1", secondary = "DP-2" }, roles)
  end)

  t.it("monitor.removed drops a role whose output just disconnected", function()
    local roles = roles_after_event(
      "quantum-desktop",
      { { name = "DP-1", width = 5120 }, { name = "DP-2", width = 1920 } },
      "monitor.removed",
      { { name = "DP-1", width = 5120 } }
    )
    t.eq({ primary = "DP-1" }, roles)
  end)
end)

t.describe("conf.host.build publishes the monitor role map -- LEO-368", function()
  t.it("desk-dual: both roles resolve to their connected outputs", function()
    local roles =
      published_roles("quantum-desktop", { { name = "DP-1", width = 5120 }, { name = "DP-2", width = 1920 } })
    t.eq({ primary = "DP-1", secondary = "DP-2" }, roles)
  end)

  t.it("laptop-solo: the unconnected secondary is omitted, not defaulted", function()
    local roles = published_roles("quantum-laptop", { { name = "eDP-1", width = 1920 } })
    t.eq({ primary = "eDP-1" }, roles)
  end)

  t.it("the case panel (ignored_monitors) never earns a role even though it is connected", function()
    local roles = published_roles(
      "quantum-desktop",
      { { name = "DP-1", width = 5120 }, { name = "DP-2", width = 1920 }, { name = "HDMI-A-1", width = 1920 } }
    )
    t.eq({ primary = "DP-1", secondary = "DP-2" }, roles)
  end)
end)
