---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- Persisted deck order (LEO-...): the store seam itself — get/record/
--- set_scroll/forget round-tripping through an in-memory fake of the
--- `deck-order` store handle, the dirty-guard that keeps an unchanged
--- rewrite from bumping the file's mtime, and the reload-survival contract
--- (what a recorded column must hand back after the composite restarts).
--- No compositor, no timers — a plain module under a hand-made store fake.
local t = require("tests.harness")

---Install an in-memory `deck-order` store backed by `doc` and load the
---module for real. Returns the module, a counter of how many times the
---store's `put` ran (the mtime-visible write the dirty guard exists to
---suppress), and the live document so a test can prove a reload — a fresh
---module over the SAME document — hands the recorded state back.
---@param doc table the initial deck-order document
---@return table deck_order
---@return function puts
---@return table state `.doc`, live document after every put
local function fresh(doc)
  local state = { doc = doc, puts = 0 }
  package.loaded["hypr.lib.store"] = {
    define = function(name)
      if name == "deck-order" then
        return {
          get = function(_, key)
            return key == nil and state.doc or state.doc[key]
          end,
          put = function(_, next_doc)
            state.puts = state.puts + 1
            state.doc = next_doc
          end,
          set = function() end,
        }
      end
      return {
        get = function()
          return {}
        end,
        put = function() end,
        set = function() end,
      }
    end,
  }
  package.loaded["hypr.scene.deck_order"] = nil
  return require("hypr.scene.deck_order"), function()
    return state.puts
  end, state
end

t.describe("deck_order: read and write", function()
  t.it("reads nothing back before anything was recorded", function()
    local order = fresh({})
    t.eq(nil, order.get("code", 1))
    t.eq({}, order.get_all("code"))
  end)

  t.it("records an order and a scroll, read back by column", function()
    local order = fresh({})
    order.record("code", 1, { "0x1", "0x2", "0x3" }, 2)
    local record = order.get("code", 1)
    t.eq({ "0x1", "0x2", "0x3" }, record.order)
    t.eq(2, record.scroll)
    t.eq(2, order.get_all("code")[1].scroll)
  end)

  t.it("set_scroll moves the visible index and keeps the recorded order", function()
    local order = fresh({})
    order.record("code", 1, { "0x1", "0x2" }, 1)
    order.set_scroll("code", 1, 2)
    local record = order.get("code", 1)
    t.eq({ "0x1", "0x2" }, record.order)
    t.eq(2, record.scroll)
  end)

  t.it("columns and scenes are keyed independently", function()
    local order = fresh({})
    order.record("code", 1, { "0x1" }, 1)
    order.record("code", 2, { "0x9" }, 1)
    order.record("media", 1, { "0x5" }, 1)
    t.eq(nil, order.get("code", 3))
    t.eq("0x9", order.get("code", 2).order[1])
    t.eq("0x5", order.get("media", 1).order[1])
  end)

  t.it("returned records are copies: mutating one cannot corrupt the store", function()
    local order = fresh({})
    order.record("code", 1, { "0x1", "0x2" }, 1)
    local first = order.get_all("code")[1]
    first.order[1] = "corrupted"
    t.eq("0x1", order.get("code", 1).order[1])
  end)
end)

t.describe("deck_order: the dirty guard", function()
  t.it("an identical rewrite is a no-op — the mtime-visible write is spared", function()
    local order, puts = fresh({})
    order.record("code", 1, { "0x1", "0x2" }, 2)
    t.eq(1, puts())
    order.record("code", 1, { "0x1", "0x2" }, 2)
    t.eq(1, puts(), "rewriting the same order and scroll must not write")
  end)

  t.it("a different order or a different scroll writes", function()
    local order, puts = fresh({})
    order.record("code", 1, { "0x1", "0x2" }, 2)
    order.record("code", 1, { "0x1" }, 2)
    t.eq(2, puts(), "a changed order writes")
    order.set_scroll("code", 1, 1)
    order.set_scroll("code", 1, 1)
    t.eq(3, puts(), "a changed scroll writes once; repeating it does not")
  end)
end)

t.describe("deck_order: forget", function()
  t.it("prunes a closed address from every scene and column", function()
    local order = fresh({})
    order.record("code", 1, { "0x1", "0x2", "0x3" }, 2)
    order.record("code", 2, { "0x1" }, 1)
    order.record("media", 1, { "0x1", "0x9" }, 1)
    order.forget("0x1")
    t.eq({ "0x2", "0x3" }, order.get("code", 1).order)
    t.eq({}, order.get("code", 2).order)
    t.eq({ "0x9" }, order.get("media", 1).order)
    t.eq(1, order.get("media", 1).scroll, "a prune keeps the recorded scroll")
  end)

  t.it("an address nowhere recorded writes nothing", function()
    local order, puts = fresh({})
    order.record("code", 1, { "0x1" }, 1)
    order.forget("0x99")
    t.eq(1, puts(), "no record mentioned the address, so no write")
    order.forget(nil)
    t.eq(1, puts(), "a nil address is ignored outright")
  end)
end)

t.describe("deck_order: reload survival", function()
  t.it("a fresh module over the same document hands the recorded state back", function()
    -- A compositor reload re-requires the module but the JSON file — the
    -- fake's live document here — survives: this is the whole persistence
    -- contract, and the same `state.doc` the first instance wrote proves it.
    local first, _, state = fresh({})
    first.record("code", 1, { "0x1", "0x2", "0x3" }, 3)
    local doc = state.doc
    package.loaded["hypr.scene.deck_order"] = nil
    local second, _, state2 = fresh(doc)
    local record = second.get("code", 1)
    t.eq({ "0x1", "0x2", "0x3" }, record.order)
    t.eq(3, record.scroll)
    t.eq(0, state2.puts, "reading a recorded column never writes")
  end)

  t.it("reset drops every record", function()
    local order = fresh({})
    order.record("code", 1, { "0x1" }, 1)
    order.reset()
    t.eq(nil, order.get("code", 1))
    t.eq({}, order.get_all("code"))
  end)
end)

return t
