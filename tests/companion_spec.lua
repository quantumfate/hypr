-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- Scene companions: the declared spawn lifecycle (LEO-296).
---
--- Presence is derived from live windows, never remembered — the close
--- decision and reload-safety both come from that. What is under test is
--- the decision function, the caller's pending filter and its finite
--- lifetime, and identity matching (companion windows off the scene count
--- for nothing).
local t = require("tests.harness")

local SPEC = {
  name = "gaming",
  blocks = {
    {
      classes = { "Dofus.x64" },
      order = 1,
      spawn = {
        class = "zen-twilight-media",
        command = "zen-twilight -P Media --name zen-twilight-media --new-window",
      },
    },
    -- Not the companion: this block names its own tile and declines the
    -- group. The companion class may coincide with a real member block; the
    -- lifecycle only ever reads the spawn-carrying block.
    { classes = { "zen-twilight-media" }, order = 2, slot = "dofus/browser", guard = "deny" },
  },
}

---The scenes live in the declaration's `base.scenes`; the stub hands the
---fixture over in the shape the real store handle answers, and the engine
---reads it the way the running config does.
local function scene_spec(with)
  package.loaded["hypr.lib.store"] = nil
  package.loaded["hypr.scene.companion"] = nil
  package.loaded["hypr.scene.spec"] = nil
  package.loaded["hypr.lib.store"] = {
    define = function()
      return {
        get = function()
          return { base = { scenes = with or { gaming = SPEC } } }
        end,
        put = function() end,
      }
    end,
  }
  return require("hypr.scene.spec").load().gaming, require("hypr.scene.companion")
end

local function dofus(addr)
  return { workspace = { name = "gaming" }, class = "Dofus.x64", address = addr }
end

local function media_on_gaming(addr)
  return { workspace = { name = "gaming" }, class = "zen-twilight-media", address = addr }
end

local function media_on_media(addr)
  return { workspace = { name = "media" }, class = "zen-twilight-media", address = addr }
end

---A spawn capped at `max_spawns`, mirroring dofus: the companion class is
---also a real tile block, which is what lets the companion's own open event
---re-converge the scene (the same shape the cap's one-at-a-time fill rides).
---@param max_spawns number
---@return table scenes
local function capped_spec(max_spawns)
  return {
    gaming = {
      name = "gaming",
      blocks = {
        {
          classes = { "Dofus.x64" },
          group = true,
          order = 1,
          spawn = { class = "zen-twilight-media", command = "zen-twilight ...", max_spawns = max_spawns },
        },
        { classes = { "zen-twilight-media" }, order = 2, guard = "deny" },
      },
    },
  }
end

t.describe("the companion lifecycle", function()
  local function fresh(with)
    ---@return any spec, any companion
    return scene_spec(with)
  end

  t.it("asks for the spawn while a member stands and no companion does", function()
    local spec, companion = fresh()
    local d = companion.decisions(spec, "gaming", { dofus("0xa1") })[1]
    t.eq("spawn", d.action)
    t.eq("zen-twilight -P Media --name zen-twilight-media --new-window", d.command)
    t.eq("gaming:zen-twilight-media", d.pending_key)
  end)

  t.it("a companion already on the scene satisfies the scan — never a duplicate", function()
    local spec, companion = fresh()
    local d = companion.decisions(spec, "gaming", { dofus("0xa1"), media_on_gaming("0xb1") })
    t.eq(0, #d, "the desk already shows the companion")
  end)

  t.it("a companion on another workspace is not the scene's companion", function()
    local spec, companion = fresh()
    local d = companion.decisions(spec, "gaming", { dofus("0xa1"), media_on_media("0xb9") })
    t.eq("spawn", d[1].action)
  end)

  t.it("closes the companion when the last member leaves", function()
    local spec, companion = fresh()
    local d = companion.decisions(spec, "gaming", { media_on_gaming("0xb1") })
    t.eq("close", d[1].action)
    t.eq("0xb1", d[1].addresses[1])
  end)

  t.it("a memberless scene collects no companion", function()
    local spec, companion = fresh()
    t.eq(0, #companion.decisions(spec, "gaming", {}))
  end)

  t.it("a pending spawn filters duplicates until the caller clears it", function()
    -- The caller tracks one thing: a spawn in flight. There is no expiry
    -- timer — the events clear the marker (the companion maps, or the scene
    -- it was spawned for emptied) — so the filter's semantics are plain:
    -- a marker blocks the next spawn decision, presence is derived, and
    -- clearing is the caller's move.
    local pending = {}
    local spec, companion = fresh()
    companion.expire("gaming:zen-twilight-media", pending)
    t.eq(true, pending["gaming:zen-twilight-media"], "the marker was armed")

    local d = companion.filter(companion.decisions(spec, "gaming", { dofus("0xa1"), dofus("0xa2") }), pending)
    t.eq(0, #d, "no second spawn while one is in flight")

    -- A close arriving for the same key does the caller's clear: no marker
    -- forces a spawn that presence already disproves, and vice versa.
    d = companion.filter(companion.decisions(spec, "gaming", { media_on_gaming("0xb1") }), pending)
    t.eq("close", d[1].action, "the marker never blocks a close")
    pending["gaming:zen-twilight-media"] = nil
    d = companion.filter(companion.decisions(spec, "gaming", { dofus("0xa1"), dofus("0xa2") }), pending)
    t.eq(1, #d, "once cleared, the next scan may spawn again")
  end)

  t.it("a close decision is not filtered and clears its caller state", function()
    -- The close is the caller's own marker that the companion showed up, a
    -- spawn state that should not block a close decision.
    local pending = { ["gaming:zen-twilight-media"] = true }
    local spec, companion = fresh()
    local d = companion.filter(companion.decisions(spec, "gaming", { media_on_gaming("0xb1") }), pending)
    t.eq("close", d[1].action)
  end)

  t.it("an unrelated window is not mistaken for the companion", function()
    local spec, companion = fresh()
    local d = companion.decisions(
      spec,
      "gaming",
      { dofus("0xa1"), { workspace = { name = "gaming" }, class = "something-else", address = "0xc1" } }
    )
    t.eq("spawn", d[1].action)
  end)

  t.describe("max_spawns cap (LEO-411)", function()
    local function fresh_capped(max_spawns)
      return scene_spec(capped_spec(max_spawns))
    end

    ---@param n integer
    ---@return table[]
    local function media(n)
      local out = {}
      for i = 1, n do
        out[i] = media_on_gaming(("0xc%d"):format(i))
      end
      return out
    end

    t.it("asks for a spawn below the cap, not only at zero", function()
      local spec, companion = fresh_capped(3)
      local d = companion.decisions(spec, "gaming", { dofus("0xa1"), media(2)[1], media(2)[2] })
      t.eq("spawn", d[1].action)
      t.eq("zen-twilight ...", d[1].command)
    end)

    t.it("asks for no further spawn once the cap is met", function()
      local spec, companion = fresh_capped(3)
      local d = companion.decisions(spec, "gaming", { dofus("0xa1"), media(3)[1], media(3)[2], media(3)[3] })
      t.eq(0, #d, "at the cap the scan is quiet")
    end)

    t.it("never closes a hand-opened excess above the cap", function()
      -- Four live companions, cap three: the close branch belongs to member
      -- presence, and a derived count cannot tell the engine's spawns from
      -- the user's — so the scan neither spawns nor closes.
      local spec, companion = fresh_capped(3)
      local d =
        companion.decisions(spec, "gaming", { dofus("0xa1"), media(4)[1], media(4)[2], media(4)[3], media(4)[4] })
      t.eq(0, #d, "an above-cap count is not a grounding offence")
    end)

    t.it("the last member leaving closes every companion whatever the cap", function()
      local spec, companion = fresh_capped(3)
      local d = companion.decisions(spec, "gaming", media(3))
      t.eq("close", d[1].action)
      t.eq(3, #d[1].addresses)
    end)

    t.it("the in-flight marker admits one spawn per convergence against the cap", function()
      local pending = {}
      local spec, companion = fresh_capped(3)
      companion.expire("gaming:zen-twilight-media", pending)
      local d =
        companion.filter(companion.decisions(spec, "gaming", { dofus("0xa1"), media(2)[1], media(2)[2] }), pending)
      t.eq(0, #d, "below the cap but one spawn already in flight: nothing new")
      pending["gaming:zen-twilight-media"] = nil
      d = companion.filter(companion.decisions(spec, "gaming", { dofus("0xa1"), media(2)[1], media(2)[2] }), pending)
      t.eq(1, #d, "once the marker clears, the next convergence may fill again")
    end)

    t.it("a claimed companion counts before it is home, so the gap spawns nothing", function()
      -- Between a claimed companion's open and the move that sends it home it
      -- stands on whatever workspace its pin rule chose, carrying the slot tag
      -- the claim stamped. Counting workspace membership alone read that as
      -- "no companion" and launched a second one in the gap.
      local spec, companion = fresh()
      local claimed = media_on_media("0xd1")
      claimed.tags = { "slot:gaming/browser" }
      t.eq(0, #companion.decisions(spec, "gaming", { dofus("0xa1"), claimed }))
    end)

    t.it("an untagged window of the class elsewhere is not this scene's companion", function()
      local spec, companion = fresh()
      t.eq("spawn", companion.decisions(spec, "gaming", { dofus("0xa1"), media_on_media("0xd2") })[1].action)
    end)

    t.it("an omitted max_spawns keeps exactly today's behaviour — one companion", function()
      local spec, companion = fresh()
      t.eq(1, spec.blocks[1].spawn.max_spawns, "the default cap is one")
      t.eq(0, #companion.decisions(spec, "gaming", { dofus("0xa1"), media_on_gaming("0xb1") }))
      t.eq("spawn", companion.decisions(spec, "gaming", { dofus("0xa1") })[1].action)
    end)
  end)
end)
