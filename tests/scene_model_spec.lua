-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- The scene model (LEO-245): what arrangement the scene asks for next.
---
--- The model is pure — a snapshot and a spec in, one intent out — so these
--- specs are plain tables. No stub compositor, no timers, no dispatch: if a
--- decision is wrong it is wrong here, in isolation from how it would be
--- carried out.
local t = require("tests.harness")

_G.config = { host = { workspaces = { scenes = {} } } }
local spec_lib = require("hypr.scene.spec")
local model = require("hypr.scene.model")

---@param blocks table[]
---@param barred string[]?
local function scene(blocks, barred)
  package.loaded["hypr.scene.spec"] = nil
  _G.config = {
    host = { workspaces = { scenes = { { default_name = "gaming", blocks = blocks, barred = barred } } } },
  }
  local lib = require("hypr.scene.spec")
  return lib.load().gaming, lib
end

---A window fixture. Geometry defaults keep the two-tile shares satisfied, so
---a test that is not about `share` never trips over it.
local function win(over)
  local w = {
    address = over.address,
    class = over.class,
    workspace = over.workspace or "gaming",
    workspace_id = over.workspace_id or 4,
    floating = over.floating or false,
    group = over.group,
    x = over.x or 0,
    y = over.y or 0,
    w = over.w or 670,
    h = over.h or 1000,
  }
  return w
end

local function snap(windows, active)
  return { active = active or "gaming", windows = windows }
end

local GROUPED = { classes = { "Dofus.x64" }, group = true, order = 1, share = 0.67, collect = true }
local BROWSER = { classes = { "zen-gaming-media" }, order = 2, share = 0.33 }

local function dofus(addr, over)
  over = over or {}
  over.address, over.class = addr, "Dofus.x64"
  return win(over)
end

local function browser(addr, over)
  over = over or {}
  over.address, over.class = addr, "zen-gaming-media"
  over.x = over.x or 670
  over.w = over.w or 330
  return win(over)
end

t.describe("visibility", function()
  t.it("asks for nothing while the scene is behind the user", function()
    local spec = scene({ GROUPED, BROWSER })
    -- Two ungrouped Dofus clients: plenty owed, none of it actionable, because
    -- correcting a hidden workspace means focusing a window the user cannot
    -- see — and being dragged there is how the engine used to "freak out".
    local s = snap({ dofus("0x1"), dofus("0x2") }, "code")
    t.eq(nil, model.intent(spec, s, {}))
  end)

  t.it("acts once the scene is the workspace in front of the user", function()
    local spec = scene({ GROUPED, BROWSER })
    local intent = model.intent(spec, snap({ dofus("0x1"), dofus("0x2") }), {})
    t.ok(intent, "expected a correction")
    t.eq("join", intent.op)
  end)
end)

t.describe("grouping", function()
  t.it("folds an ungrouped member into the block's group", function()
    local spec = scene({ GROUPED })
    local intent = model.intent(spec, snap({ dofus("0x1", { group = "0x1" }), dofus("0x2") }), {})
    t.eq("join", intent.op)
    t.eq("0x2", intent.address)
    t.eq("0x1", intent.target)
  end)

  t.it("converges the smaller group on the larger when a block split in two", function()
    -- The failure this fixes: two groups form for one block (auto_group wins a
    -- race at map time), and an engine that remembered one set as
    -- authoritative fought the other forever.
    local spec = scene({ GROUPED })
    local windows = {
      dofus("0x1", { group = "0x1" }),
      dofus("0x2", { group = "0x1" }),
      dofus("0x3", { group = "0x3" }),
    }
    local intent = model.intent(spec, snap(windows), {})
    t.eq("join", intent.op)
    t.eq("0x3", intent.address, "the minority group is the one that moves")
    t.eq("0x1", intent.target)
  end)

  t.it("ejects a foreigner that auto_group swallowed", function()
    local spec = scene({ GROUPED, BROWSER })
    local windows = {
      dofus("0x1", { group = "0x1" }),
      dofus("0x2", { group = "0x1" }),
      browser("0x9", { group = "0x1" }),
    }
    local intent = model.intent(spec, snap(windows), {})
    t.eq("evict", intent.op)
    t.eq("0x9", intent.address)
  end)

  t.it("is satisfied once every member shares one group", function()
    local spec = scene({ GROUPED, BROWSER })
    local windows = {
      dofus("0x1", { group = "0x1" }),
      dofus("0x2", { group = "0x1" }),
      browser("0x9"),
    }
    t.eq(nil, model.intent(spec, snap(windows), {}))
  end)

  t.it("leaves a non-group block's windows as separate tiles", function()
    local spec = scene({ { classes = { "zen-gaming-media" }, order = 1 } })
    local windows = { browser("0x8", { x = 0, w = 500 }), browser("0x9", { x = 500, w = 500 }) }
    t.eq(nil, model.intent(spec, snap(windows), {}))
  end)
end)

t.describe("collection", function()
  t.it("brings an owned member home when the block asked for it", function()
    local spec = scene({ GROUPED })
    local windows = {
      dofus("0x1", { group = "0x1" }),
      dofus("0x7", { workspace = "code", workspace_id = 2 }),
    }
    local intent = model.intent(spec, snap(windows), { ["0x7"] = true })
    t.eq("collect", intent.op)
    t.eq("0x7", intent.address)
    t.eq("gaming", intent.workspace)
  end)

  t.it("never claims a window it does not own", function()
    -- A window matching the scene's classes that the scene never received is
    -- the user's choice, not arrangement debt. This is the difference between
    -- "the scene tidies itself" and "the desk drags your terminals around".
    local spec = scene({ GROUPED })
    local windows = {
      dofus("0x1", { group = "0x1" }),
      dofus("0x7", { workspace = "code", workspace_id = 2 }),
    }
    t.eq(nil, model.intent(spec, snap(windows), {}))
  end)

  t.it("leaves a member parked on a special workspace alone", function()
    local spec = scene({ GROUPED })
    local windows = {
      dofus("0x1", { group = "0x1" }),
      dofus("0x7", { workspace = "special:magic", workspace_id = -98 }),
    }
    t.eq(nil, model.intent(spec, snap(windows), { ["0x7"] = true }))
  end)

  t.it("collects nothing while the scene is empty", function()
    local spec = scene({ GROUPED })
    local windows = { dofus("0x7", { workspace = "code", workspace_id = 2 }) }
    t.eq(nil, model.intent(spec, snap(windows), { ["0x7"] = true }))
  end)

  t.it("does not collect for a block that did not opt in", function()
    local spec = scene({ { classes = { "Dofus.x64" }, group = true, order = 1 } })
    local windows = {
      dofus("0x1", { group = "0x1" }),
      dofus("0x7", { workspace = "code", workspace_id = 2 }),
    }
    t.eq(nil, model.intent(spec, snap(windows), { ["0x7"] = true }))
  end)
end)

t.describe("order", function()
  t.it("moves a block that sits on the wrong side", function()
    local spec = scene({
      { classes = { "Dofus.x64" }, group = true, order = 1 },
      { classes = { "zen-gaming-media" }, order = 2 },
    })
    local windows = {
      browser("0x9", { x = 0, w = 330 }),
      dofus("0x1", { group = "0x1", x = 330, w = 670 }),
    }
    local intent = model.intent(spec, snap(windows), {})
    t.eq("reorder", intent.op)
    t.eq("0x9", intent.address)
    t.eq("r", intent.dir)
  end)

  t.it("is satisfied by the declared sequence", function()
    local spec = scene({
      { classes = { "Dofus.x64" }, group = true, order = 1 },
      { classes = { "zen-gaming-media" }, order = 2 },
    })
    local windows = { dofus("0x1", { group = "0x1", x = 0, w = 670 }), browser("0x9", { x = 670, w = 330 }) }
    t.eq(nil, model.intent(spec, snap(windows), {}))
  end)

  t.it("says nothing about a block with no window open", function()
    local spec = scene({ GROUPED, BROWSER })
    t.eq(nil, model.intent(spec, snap({ dofus("0x1", { group = "0x1", x = 0, w = 1000 }) }), {}))
  end)
end)

t.describe("share", function()
  t.it("resizes a block that drifted off its fraction", function()
    local spec = scene({ GROUPED, BROWSER })
    local windows = {
      dofus("0x1", { group = "0x1", x = 0, w = 500 }),
      browser("0x9", { x = 500, w = 500 }),
    }
    local intent = model.intent(spec, snap(windows), {})
    t.eq("resize", intent.op)
    t.eq("0x1", intent.address)
    t.eq(670, intent.width)
  end)

  t.it("measures against every tile, not only the scene's", function()
    -- A foreign tile on the workspace is part of the span the shares divide.
    -- Measuring block-against-block instead made the target shrink with every
    -- window that was not in a block.
    local spec = scene({ GROUPED, BROWSER })
    local windows = {
      dofus("0x1", { group = "0x1", x = 0, w = 500 }),
      browser("0x9", { x = 500, w = 300 }),
      win({ address = "0xf", class = "mpv", x = 800, w = 200 }),
    }
    local intent = model.intent(spec, snap(windows), {})
    t.eq("resize", intent.op)
    t.eq(670, intent.width, "0.67 of the full 1000px span")
  end)

  t.it("leaves a lone tile at full width", function()
    -- A 0.67 block alone on the workspace must not shrink to two thirds of
    -- itself; there is nothing to share with.
    local spec = scene({ GROUPED, BROWSER })
    t.eq(nil, model.intent(spec, snap({ dofus("0x1", { group = "0x1", x = 0, w = 1000 }) }), {}))
  end)

  t.it("tolerates drift inside the dead band", function()
    local spec = scene({ GROUPED, BROWSER })
    local windows = {
      dofus("0x1", { group = "0x1", x = 0, w = 680 }),
      browser("0x9", { x = 680, w = 320 }),
    }
    t.eq(nil, model.intent(spec, snap(windows), {}))
  end)
end)

t.describe("priority", function()
  t.it("settles tile count before tile geometry", function()
    -- Order and share are both measured in tiles, so a pending join would
    -- make either one a measurement of a layout about to change.
    local spec = scene({ GROUPED, BROWSER })
    local windows = {
      dofus("0x1", { group = "0x1", x = 0, w = 400 }),
      dofus("0x2", { x = 400, w = 300 }),
      browser("0x9", { x = 700, w = 300 }),
    }
    t.eq("join", model.intent(spec, snap(windows), {}).op)
  end)

  t.it("brings members home before arranging them", function()
    local spec = scene({ GROUPED, BROWSER })
    local windows = {
      dofus("0x1", { group = "0x1", x = 0, w = 400 }),
      browser("0x9", { x = 400, w = 600 }),
      dofus("0x7", { workspace = "code", workspace_id = 2 }),
    }
    t.eq("collect", model.intent(spec, snap(windows), { ["0x7"] = true }).op)
  end)
end)

t.describe("floating windows", function()
  t.it("are not part of the arrangement", function()
    local spec = scene({ GROUPED, BROWSER })
    local windows = {
      dofus("0x1", { group = "0x1", x = 0, w = 670 }),
      browser("0x9", { x = 670, w = 330 }),
      win({ address = "0xf", class = "Dofus.x64", floating = true, x = 200, w = 400 }),
    }
    t.eq(nil, model.intent(spec, snap(windows), {}))
  end)
end)

t.describe("class matching", function()
  t.it("takes a literal class over a pattern reading of it", function()
    -- "Kitty-Main" contains `-`, a Lua-pattern quantifier; read as a pattern
    -- it would not match itself.
    t.ok(spec_lib.class_matches("Kitty-Main", { "Kitty-Main" }))
  end)

  t.it("still matches a genuine pattern", function()
    t.ok(spec_lib.class_matches("Proj-nvim", { "Proj-[A-Za-z0-9_-]+" }))
    t.ok(not spec_lib.class_matches("Proj nvim", { "Proj-[A-Za-z0-9_-]+" }))
  end)

  t.it("anchors, so a longer class does not match a shorter pattern", function()
    t.ok(not spec_lib.class_matches("zen-gaming-media-extra", { "zen-gaming-media" }))
  end)
end)

t.describe("digest", function()
  t.it("changes when a tile moves", function()
    local spec = scene({ GROUPED, BROWSER })
    local a = model.digest(spec, snap({ dofus("0x1", { x = 0, w = 670 }) }))
    local b = model.digest(spec, snap({ dofus("0x1", { x = 10, w = 670 }) }))
    t.ok(a ~= b)
  end)

  t.it("changes when grouping changes, though no tile moved", function()
    -- A join collapses two windows into one tile without necessarily moving
    -- anything on the first frame; a digest blind to grouping would call that
    -- settled and re-issue the join.
    local spec = scene({ GROUPED })
    local a = model.digest(spec, snap({ dofus("0x1"), dofus("0x2") }))
    local b = model.digest(spec, snap({ dofus("0x1", { group = "0x1" }), dofus("0x2", { group = "0x1" }) }))
    t.ok(a ~= b)
  end)

  t.it("is stable across window order", function()
    local spec = scene({ GROUPED, BROWSER })
    local one = { dofus("0x1", { x = 0, w = 670 }), browser("0x9", { x = 670, w = 330 }) }
    local two = { browser("0x9", { x = 670, w = 330 }), dofus("0x1", { x = 0, w = 670 }) }
    t.eq(model.digest(spec, snap(one)), model.digest(spec, snap(two)))
  end)
end)
