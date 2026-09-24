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
---stub, and returns one published `geometry` store section.
---@param key "monitors"|"workspaces"|"global"|"roles"
---@param hostname string
---@param monitors HL.Monitor[]
---@return table
local function published(key, hostname, monitors)
  for name in pairs(package.loaded) do
    if name == "hypr" or name:match("^hypr%.") or name:match("^conf%.") then
      package.loaded[name] = nil
    end
  end

  _G.hl = require("tests.hl_stub").new()
  hl.monitors = monitors
  hl.config_values["general.gaps_out"] = { top = 8, right = 40, bottom = 40, left = 40 }
  hl.config_values["general.gaps_in"] = 24
  hl.config_values["general.border_size"] = 1

  local util = require("hypr.lib.util")
  local real_hostname = util.hostname
  util.hostname = function()
    return hostname
  end

  require("conf.host").build()
  util.hostname = real_hostname

  local Store = require("hypr.lib.store")
  return Store.define("geometry"):get(key)
end

local function published_monitors(hostname, monitors)
  return published("monitors", hostname, monitors)
end

t.describe("conf.host.build publishes per-monitor gaps -- LEO-340", function()
  t.it("desk-dual: each monitor publishes its profile's own sides", function()
    local monitors = published_monitors("quantum-desktop", { { width = 5120 }, { width = 1920 } })
    t.eq({ left = 30, right = 30 }, monitors["DP-1"])
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

t.describe("conf.host.build publishes resolved per-workspace gaps", function()
  ---Seed a hyprfocus declaration in the sandboxed store so `resolved_gaps`
  ---has scenes to fold; build() reads it through the store handle like the
  ---engine does.
  ---@param scenes table
  local function seed_scenes(scenes)
    local json = require("hypr.lib.json")
    local f = assert(io.open(dir .. "/hyprfocus.json", "w"))
    f:write(json.encode({ base = { scenes = scenes } }))
    f:close()
  end

  t.it("a declared scene publishes its own gaps_out over the host spec, per layout.sides", function()
    seed_scenes({ code = { gaps_out = { top = 0, right = 60, bottom = 25, left = 25 } } })
    local workspaces = published("workspaces", "quantum-desktop", { { width = 5120 }, { width = 1920 } })
    -- The visible edge adds what the layout's own gap misses: the rule's
    -- gaps_out (DP-1 { left = 30, right = 30 } in the desk-dual primary profile)
    -- plus the rule's gaps_in (20) and the 1px border on each inset side.
    t.eq({ top = 13, right = 111, bottom = 61, left = 76 }, workspaces["code"])
  end)

  t.it("a deck scene honours its sided gaps_out, per layout.sides, same as a scene layout", function()
    seed_scenes({ code = { layout = "deck", gaps_out = { top = 0, right = 60, bottom = 25, left = 25 } } })
    local workspaces = published("workspaces", "quantum-desktop", { { width = 5120 }, { width = 1920 } })
    t.eq({ top = 13, right = 111, bottom = 61, left = 76 }, workspaces["code"])
  end)

  t.it("a scene with no gaps_out resolves the host workspace-spec, keyed by default_name", function()
    -- The workspace inset re-adds the rule's gaps_out (the number the monitor
    -- map publishes) and, on an inset side, the rule's gaps_in (20 in the
    -- desk-dual primary profile) and the 1px border, on both sides now that the
    -- primary profile insets its right edge too. Tracks base.lua's desk-dual primary profile,
    -- like the monitor map above.
    seed_scenes({ code = {} })
    local workspaces = published("workspaces", "quantum-desktop", { { width = 5120 }, { width = 1920 } })
    t.eq({ top = 45, right = 81, bottom = 51, left = 81 }, workspaces["code"])
  end)

  t.it("a workspace with no declared scene is absent: nothing to subscribe to", function()
    local workspaces = published("workspaces", "quantum-desktop", { { width = 5120 }, { width = 1920 } })
    t.eq(nil, workspaces["media"])
  end)

  t.it("host build preserves docks published by the scene engine", function()
    -- conf/host.lua runs on every reload; it must not wipe docks that the
    -- scene engine will only re-publish on the next layout pass.
    local Store = require("hypr.lib.store")
    local handle = Store.define("geometry")
    handle:set({ docks = { ["DP-1"] = { bar = { x = 10 } } } })
    -- Re-run build() with a fresh engine; the dock document should survive.
    published("monitors", "quantum-desktop", { { width = 5120 }, { width = 1920 } })
    local docks = handle:get("docks")
    t.eq(10, docks and docks["DP-1"] and docks["DP-1"].bar and docks["DP-1"].bar.x)
  end)

  t.it("a runtime scene edit re-publishes on the engine's first re-read, no reload", function()
    seed_scenes({ code = { gaps_out = { top = 0, right = 60, bottom = 25, left = 25 } } })
    t.eq(
      { top = 13, right = 111, bottom = 61, left = 76 },
      published("workspaces", "quantum-desktop", { { width = 5120 }, { width = 1920 } })["code"]
    )
    -- Edit the declaration: the next load (fresh engine state per published())
    -- sees the bumped mtime, and hypr/scene/spec.lua re-publishes the resolved
    -- map into the same store — the bar's watchChanges re-emits on its own.
    seed_scenes({ code = { gaps_out = 12 } })
    t.eq(
      { top = 45, right = 63, bottom = 48, left = 63 },
      published("workspaces", "quantum-desktop", { { width = 5120 }, { width = 1920 } })["code"]
    )
  end)
end)
