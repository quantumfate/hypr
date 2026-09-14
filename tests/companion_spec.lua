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
      spawn = { class = "zen-gaming-media", command = "zen-twilight -P GamingMedia --name zen-gaming-media" },
    },
    -- Not the companion: this block names its own tile and declines the
    -- group. The companion class may coincide with a real member block; the
    -- lifecycle only ever reads the spawn-carrying block.
    { classes = { "zen-gaming-media" }, order = 2, guard = "deny" },
  },
}

---The scenes document lives in the state store now; the stub hands the
---fixture over the same shape the real store handle answers, and the engine
---reads it the way the running config does.
local function scene_spec(with)
  package.loaded["hypr.lib.store"] = nil
  package.loaded["hypr.scene.companion"] = nil
  package.loaded["hypr.scene.spec"] = nil
  package.loaded["hypr.lib.store"] = {
    define = function()
      return {
        get = function()
          return { scenes = with or { gaming = SPEC } }
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
  return { workspace = { name = "gaming" }, class = "zen-gaming-media", address = addr }
end

local function media_on_media(addr)
  return { workspace = { name = "media" }, class = "zen-gaming-media", address = addr }
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
    t.eq("zen-twilight -P GamingMedia --name zen-gaming-media", d.command)
    t.eq("gaming:zen-gaming-media", d.pending_key)
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
    companion.expire("gaming:zen-gaming-media", pending)
    t.eq(true, pending["gaming:zen-gaming-media"], "the marker was armed")

    local d = companion.filter(companion.decisions(spec, "gaming", { dofus("0xa1"), dofus("0xa2") }), pending)
    t.eq(0, #d, "no second spawn while one is in flight")

    -- A close arriving for the same key does the caller's clear: no marker
    -- forces a spawn that presence already disproves, and vice versa.
    d = companion.filter(companion.decisions(spec, "gaming", { media_on_gaming("0xb1") }), pending)
    t.eq("close", d[1].action, "the marker never blocks a close")
    pending["gaming:zen-gaming-media"] = nil
    d = companion.filter(companion.decisions(spec, "gaming", { dofus("0xa1"), dofus("0xa2") }), pending)
    t.eq(1, #d, "once cleared, the next scan may spawn again")
  end)

  t.it("a close decision is not filtered and clears its caller state", function()
    -- The close is the caller's own marker that the companion showed up, a
    -- spawn state that should not block a close decision.
    local pending = { ["gaming:zen-gaming-media"] = true }
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
end)
