-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
local t = require("tests.harness")

-- profile.lua persists through hypr/lib/store.lua; point it at a scratch dir
-- like store_spec.lua does, so this spec never touches the real state file.
local dir = t.tempdir()
local real_getenv = os.getenv
os.getenv = function(k)
  if k == "XDG_STATE_HOME" then
    return dir
  end
  return real_getenv(k)
end

local profile = require("hypr.lib.profile")

t.describe("profile.fingerprint", function()
  t.it("ultrawide + a second output is desk-dual", function()
    t.eq(profile.DESK_DUAL, profile.fingerprint({ { width = 5120 }, { width = 1920 } }))
  end)

  t.it("a single sub-2560 output is laptop-solo", function()
    t.eq(profile.LAPTOP_SOLO, profile.fingerprint({ { width = 1920 } }))
  end)

  t.it("an ultrawide alone is still desk-dual: the panel decides, not the count", function()
    -- Unplugging the second monitor does not make the 5120px one narrower, and
    -- laptop gaps on it would waste the space desk-dual exists to use.
    t.eq(profile.DESK_DUAL, profile.fingerprint({ { width = 5120 } }))
  end)

  t.it("two normal-aspect outputs, neither ultrawide, is laptop-solo", function()
    t.eq(profile.LAPTOP_SOLO, profile.fingerprint({ { width = 1920 }, { width = 1920 } }))
  end)

  t.it("exactly the ultrawide threshold counts as ultrawide", function()
    t.eq(profile.DESK_DUAL, profile.fingerprint({ { width = 3440 }, { width = 1080 } }))
  end)
end)

t.describe("profile.resolve / force", function()
  t.it("resolve() follows the live fingerprint with no override standing", function()
    hl.monitors = { { width = 1920 } }
    t.eq(profile.LAPTOP_SOLO, profile.resolve())
  end)

  t.it("force() overrides resolve() away from the live fingerprint and persists it", function()
    hl.monitors = { { width = 1920 } } -- fingerprints laptop-solo
    local ok, err = profile.force(profile.DESK_DUAL, 60)
    t.ok(ok, err)
    t.eq(profile.DESK_DUAL, profile.resolve()) -- override wins over the fingerprint
  end)

  t.it("force() refuses an unknown profile name", function()
    local ok, err = profile.force("ultrawide-solo")
    t.ok(not ok)
    t.ok(err and err:match("unknown profile"), tostring(err))
  end)

  t.it("clear() drops a standing override; resolve() returns to the fingerprint", function()
    hl.monitors = { { width = 1920 } }
    profile.force(profile.DESK_DUAL, 60)
    profile.clear()
    t.eq(profile.LAPTOP_SOLO, profile.resolve())
  end)

  t.it("a force past its own expiry is treated as unset, not honoured forever", function()
    -- force() always sets a future expiry, so simulate the passage of time by
    -- writing an already-past one directly, the way a stale store would read.
    require("hypr.lib.store").define("hypr/monitor-profile"):set({
      forced = profile.DESK_DUAL,
      forced_until = "2000-01-01T00:00:00Z",
    })
    hl.monitors = { { width = 1920 } }
    t.eq(profile.LAPTOP_SOLO, profile.resolve())
  end)
end)

t.describe("profile.announce", function()
  local emitted
  t.it("logs a 'profile' stage event while a force stands", function()
    package.loaded["hypr.lib.trace"] = {
      emit = function(r)
        emitted = r
      end,
    }
    package.loaded["hypr.lib.profile"] = nil
    profile = require("hypr.lib.profile")

    profile.force(profile.DESK_DUAL, 60)
    emitted = nil
    profile.announce()
    t.ok(emitted, "announce() should emit while a force stands")
    t.eq("profile", emitted.stage)
    t.eq("forced_active", emitted.event)
    t.eq(profile.DESK_DUAL, emitted.decision)
  end)

  t.it("emits nothing once the force is cleared", function()
    profile.clear()
    emitted = nil
    profile.announce()
    t.eq(nil, emitted)
  end)

  package.loaded["hypr.lib.trace"] = nil
end)

os.getenv = real_getenv
