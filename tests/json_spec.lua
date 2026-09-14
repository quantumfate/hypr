-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
local t = require("tests.harness")
local json = require("hypr.lib.json")

t.describe("json", function()
  t.it("round-trips scalars", function()
    t.eq(1, json.decode(json.encode(1)))
    t.eq(true, json.decode(json.encode(true)))
    t.eq("hi", json.decode(json.encode("hi")))
  end)

  t.it("round-trips nested tables (object and array)", function()
    local data = {
      name = "duo",
      members = { "iop", "eniripsa" },
      meta = { active = true, count = 2, nested = { { a = 1 }, { a = 2 } } },
    }
    local decoded = json.decode(json.encode(data))
    t.eq(data, decoded)
  end)

  t.it("escapes control characters and quotes in strings", function()
    local s = 'line1\nline2\t"quoted"\\backslash'
    t.eq(s, json.decode(json.encode(s)))
  end)

  t.it("encodes an empty table as an empty array (rxi/json.lua's array/object rule)", function()
    -- encode_table treats "has no [1] and no other keys" as an empty array,
    -- not an empty object — matches how it decodes back.
    t.eq({}, json.decode(json.encode({})))
  end)

  t.it("rejects trailing garbage", function()
    local ok = pcall(json.decode, '{"a":1} garbage')
    t.ok(not ok, "expected decode to error on trailing garbage")
  end)
end)
