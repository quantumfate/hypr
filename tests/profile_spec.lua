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

t.describe("profile.resolve / switch", function()
  t.it("resolve() follows the live fingerprint with no override standing", function()
    hl.monitors = { { width = 1920 } }
    t.eq(profile.LAPTOP_SOLO, profile.resolve())
  end)

  t.it("switch() flips resolve() away from the live fingerprint and persists it", function()
    hl.monitors = { { width = 1920 } } -- fingerprints laptop-solo
    local forced = profile.switch()
    t.eq(profile.DESK_DUAL, forced)
    t.eq(profile.DESK_DUAL, profile.resolve()) -- override wins over the fingerprint
  end)

  t.it("switch() again flips back", function()
    local forced = profile.switch()
    t.eq(profile.LAPTOP_SOLO, forced)
  end)
end)

os.getenv = real_getenv
