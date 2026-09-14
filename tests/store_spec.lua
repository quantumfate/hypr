-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
local t = require("tests.harness")

-- store.lua reads its roots once at require-time, so point both at scratch
-- dirs before requiring: QF_STORE is where the stores live now; the legacy
-- XDG dir lies next to it empty, so the migration read has nothing to adopt.
-- Stock Lua has no os.setenv, so stub os.getenv itself for the duration of
-- this process (run.lua gives each spec its own process-wide state anyway).
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

local Store = require("hypr.lib.store")

t.describe("store", function()
  t.it("get() on a missing file returns an empty table", function()
    local s = Store.define("spec/missing")
    t.eq({}, s:get())
  end)

  t.it("put() then get() round-trips a value", function()
    local s = Store.define("spec/roundtrip")
    s:put({ selected = "duo", count = 2 })
    t.eq({ selected = "duo", count = 2 }, s:get())
  end)

  t.it("set() shallow-merges a patch and persists it", function()
    local s = Store.define("spec/patch")
    s:put({ a = 1, b = 1 })
    s:set({ b = 2, c = 3 })
    t.eq({ a = 1, b = 2, c = 3 }, s:get())
  end)

  t.it("update() mutates via a function and persists the result", function()
    local s = Store.define("spec/update")
    s:put({ n = 1 })
    s:update(function(v)
      v.n = v.n + 1
      return v
    end)
    t.eq({ n = 2 }, s:get())
  end)

  t.it("a write is visible to a second handle on the same path after reload", function()
    -- Two Store.define calls for the same name share one cached handle in this
    -- process, so drive the "external writer" case through the file directly:
    -- write bytes on disk with a fresh mtime, then confirm a stale handle
    -- re-reads instead of serving its cached copy.
    local s = Store.define("spec/external")
    s:put({ v = 1 })

    -- Force a distinct mtime: same-second writes can otherwise look
    -- unchanged to the mtime check.
    os.execute("sleep 1")
    local path = dir .. "/spec/external.json"
    local f = assert(io.open(path, "w"))
    f:write('{"v": 2}')
    f:close()

    t.eq(2, s:get("v"))
  end)

  t.it("reload(true) forces a re-read even with an unchanged mtime", function()
    local s = Store.define("spec/force")
    s:put({ v = 1 })
    local cached = s:get()
    cached.v = 999 -- mutate the cached table in place, bypassing put()
    t.eq(999, s:get("v")) -- still cached — no reload triggered yet
    local reloaded = s:reload(true)
    t.eq(1, reloaded.v) -- forced reload discards the in-place mutation
  end)
end)

-- All specs share one process (see run.lua) — restore os.getenv so later
-- specs see the real environment.
os.getenv = real_getenv
