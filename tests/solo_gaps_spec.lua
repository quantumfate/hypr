--- solo_gaps: wide outer gaps for a workspace holding one tile.
---
--- The module reads the `hl` and `config` globals at event time, so one stub
--- object is enough for the whole spec as long as the wireable pieces
--- (windows, active workspace) are mutated in place. Every scenario uses its
--- own workspace id because the module caches which workspaces it widened.
local t = require("tests.harness")

local stub = require("tests.hl_stub").new()
_G.hl = stub

local active_ws = { id = 1, tiled_layout = "dwindle" }
local windows = {}
local global_gaps_out = 12

_G.config = {
  host = {
    workspaces = {
      workspace_specs = {
        { workspace = "2", gaps_out = 40 },
        { workspace = "3", engine = { solo_gaps = "none" }, gaps_out = 12 },
        { workspace = "4", gaps_out = { top = 8, right = 40, bottom = 40, left = 40 } },
        { workspace = "5", gaps_out = 40 },
      },
    },
  },
}

stub.get_active_workspace = function()
  return active_ws
end
stub.get_windows = function()
  return windows
end
stub.get_config = function()
  return global_gaps_out
end

-- solo_gaps registers at require time, then reads state live off the stub.
require("hypr.events.solo_gaps")

local function fire_open()
  local open = stub.event_handlers["window.open_early"]
  open[#open]()
end

local function last_rule()
  return stub.workspace_rules[#stub.workspace_rules]
end

local function reset()
  stub.workspace_rules = {}
  active_ws = { id = 1, tiled_layout = "dwindle" }
  windows = {}
end

t.describe("solo_gaps", function()
  t.it("frames a workspace holding a lone tiled window", function()
    reset()
    windows = { { workspace = { id = 1 }, floating = false } }
    fire_open()
    t.eq({ workspace = "1", gaps_out = 192 }, last_rule(), "global base 12 + SOLO_EXTRA 180")
  end)

  t.it("widens once: a second event does not stack the frame", function()
    reset()
    active_ws = { id = 10, tiled_layout = "dwindle" }
    windows = { { workspace = { id = 10 }, floating = false } }
    fire_open()
    fire_open()
    t.eq(1, #stub.workspace_rules)
    t.eq(192, last_rule().gaps_out)
  end)

  t.it("a group of many windows is still one tile -- LEO-191", function()
    reset()
    active_ws = { id = 11, tiled_layout = "dwindle" }
    local group = {}
    windows = {
      { workspace = { id = 11 }, floating = false, group = group },
      { workspace = { id = 11 }, floating = false, group = group },
      { workspace = { id = 11 }, floating = false, group = group },
    }
    fire_open()
    t.eq({ workspace = "11", gaps_out = 192 }, last_rule(), "three members, one tile")
  end)

  t.it("uses the spec's own gap as the frame base", function()
    reset()
    active_ws = { id = 2, tiled_layout = "dwindle" }
    windows = { { workspace = { id = 2 }, floating = false } }
    fire_open()
    t.eq({ workspace = "2", gaps_out = 220 }, last_rule(), "spec gaps_out 40 + SOLO_EXTRA 180")
  end)

  t.it("keeps a named-edge gap's shape when widening", function()
    reset()
    active_ws = { id = 4, tiled_layout = "dwindle" }
    windows = { { workspace = { id = 4 }, floating = false } }
    fire_open()
    t.eq(
      { top = 188, right = 220, bottom = 220, left = 220 },
      last_rule().gaps_out,
      "every edge grows by SOLO_EXTRA, top stays tighter"
    )
  end)

  t.it("restores the original gap when a second tile arrives and stays restored", function()
    reset()
    active_ws = { id = 5, tiled_layout = "dwindle" }
    windows = { { workspace = { id = 5 }, floating = false } }
    fire_open()
    t.eq(220, last_rule().gaps_out)

    windows = {
      { workspace = { id = 5 }, floating = false },
      { workspace = { id = 5 }, floating = false },
    }
    fire_open()
    t.eq({ workspace = "5", gaps_out = 40 }, last_rule(), "restored to what the spec asked")
    fire_open()
    t.eq(40, last_rule().gaps_out, "stays restored while there are two tiles")
  end)

  t.it("floating windows neither trigger nor cancel the frame", function()
    reset()
    active_ws = { id = 7, tiled_layout = "dwindle" }
    windows = {
      { workspace = { id = 7 }, floating = true, group = {} },
      { workspace = { id = 7 }, floating = true },
    }
    fire_open()
    t.eq(0, #stub.workspace_rules)

    active_ws = { id = 8, tiled_layout = "dwindle" }
    windows = {
      { workspace = { id = 8 }, floating = false },
      { workspace = { id = 8 }, floating = true },
    }
    fire_open()
    t.eq({ workspace = "8", gaps_out = 192 }, last_rule())
  end)

  t.it("engine.solo_gaps = 'none' opts a workspace out", function()
    reset()
    active_ws = { id = 3, tiled_layout = "dwindle" }
    windows = { { workspace = { id = 3 }, floating = false } }
    fire_open()
    t.eq(0, #stub.workspace_rules)
  end)

  t.it("self-framing layouts leave the gap alone", function()
    reset()
    active_ws = { id = 6, tiled_layout = "scrolling" }
    windows = { { workspace = { id = 6 }, floating = false } }
    fire_open()
    t.eq(0, #stub.workspace_rules)
  end)
end)
