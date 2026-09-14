-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- The compositor-side focus oracles (LEO-267).
---
--- These verdicts must match Focus.qml's — the store is one truth, and this
--- is its second language. The specs read the same fixtures the quickshell
--- suite pins (neutral never blocks, a mood never blocks its own kind, soft
--- warns through, expiry lapses, absent scene is reachable).
local t = require("tests.harness")

local POLICY = {
  neutral = { name = "Neutral", launches = { aggression = "soft", block = {} } },
  work = {
    name = "Work",
    launches = { aggression = "firm", block = { "media", "game" } },
    scenes = { gaming = "blocked", media = "blocked" },
  },
  soft = {
    name = "Soft mood",
    launches = { aggression = "soft", block = { "media" } },
  },
  gaming = { name = "Gaming" },
}

local function fresh(policy, pointer)
  for _, mod in ipairs({ "hypr.lib.store", "hypr.lib.focus_gate" }) do
    package.loaded[mod] = nil
  end
  package.loaded["hypr.lib.store"] = {
    define = function(name)
      return {
        get = function(_, key)
          local data = (name == "mood-policy") and { moods = policy } or pointer
          if key == nil then
            return data
          end
          return type(data) == "table" and data[key] or nil
        end,
      }
    end,
  }
  return require("hypr.lib.focus_gate")
end

t.describe("the launch gate", function()
  t.it("neutral blocks nothing", function()
    local gate = fresh(POLICY, { mode = "neutral" })
    t.eq(nil, gate.block_reason("media"))
    t.eq(nil, gate.block_reason("game"))
  end)

  t.it("a mood never blocks launching into itself", function()
    local gate = fresh(POLICY, { mode = "gaming" })
    t.eq(nil, gate.block_reason("game"), "entering gaming is how you start gaming")
  end)

  t.it("kind vocabulary and mood ids meet at kindOwner", function()
    -- The trim stopped the two vocabularies overlapping; the owner link is
    -- the one fact that keeps "a mood never blocks its own kind" true.
    local gate = fresh(POLICY, { mode = "gaming" })
    t.eq(nil, gate.block_reason("game"))
  end)

  t.it("firm refuses a blocked kind", function()
    local gate = fresh(POLICY, { mode = "work" })
    local reason = gate.block_reason("media")
    t.ok(reason and reason:match("Work"), tostring(reason))
  end)

  t.it("soft warns and lets through", function()
    local gate = fresh(POLICY, { mode = "soft" })
    t.eq(nil, gate.block_reason("media"))
  end)

  t.it("an expired pointer lapses the block on its own", function()
    local gate = fresh(POLICY, {
      mode = "work",
      ["until"] = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() - 60),
    })
    t.eq(nil, gate.block_reason("media"), "a stale mood stops blocking")
  end)

  t.it("a malformed expiry is still live, not a free pass", function()
    -- The shell owns the formatting; the comparator errs on the side that
    -- keeps the user's chosen block standing.
    local gate = fresh(POLICY, { mode = "work", ["until"] = "not-a-date" })
    t.ok(gate.block_reason("media"))
  end)

  t.it("fails open without a policy", function()
    local gate = fresh(nil, { mode = "work" })
    t.eq(nil, gate.block_reason("media"))
  end)
end)

t.describe("scene reachability", function()
  t.it("absent-from-policy is an open door, like the shell's verdict", function()
    local gate = fresh(POLICY, { mode = "gaming" })
    t.eq(nil, gate.blocked_scene("media"))
  end)

  t.it("a mood withholds the scene it names blocked", function()
    local gate = fresh(POLICY, { mode = "work" })
    t.ok(gate.blocked_scene("gaming"))
    t.ok(gate.blocked_scene("media"))
  end)
end)
