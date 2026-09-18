--- The boot decision (`hypr/hyprfocus/boot.lua`): login enters `work` unless
--- a still-running timed mode resumes. Pure, so no `hl` stub is needed — only
--- the same expiry test `hypr/hyprfocus/init.lua` hands its callers.
local t = require("tests.harness")
local boot = require("hypr.hyprfocus.boot")

local KNOWN_MODES = { work = {}, game = {}, study = {}, neutral = {} }

local function not_expired()
  return false
end
local function expired()
  return true
end

t.describe("hyprfocus.boot", function()
  t.it("missing store enters work", function()
    local action, mode = boot.decide(nil, KNOWN_MODES, not_expired)
    t.eq("enter_work", action)
    t.eq("work", mode)
  end)

  t.it("stale expired timed pointer enters work, not its previous", function()
    local pointer = { mode = "game", ["until"] = "2020-01-01T00:00:00Z", previous = "study" }
    local action, mode = boot.decide(pointer, KNOWN_MODES, expired)
    t.eq("enter_work", action)
    t.eq("work", mode)
  end)

  t.it("unexpired timed pointer resumes and the executor keeps its previous", function()
    local pointer = { mode = "game", ["until"] = "2999-01-01T00:00:00Z", previous = "study" }
    local action, mode = boot.decide(pointer, KNOWN_MODES, not_expired)
    t.eq("resume", action)
    t.eq("game", mode)
    -- boot.decide never touches the pointer table itself.
    t.eq("study", pointer.previous)
  end)

  t.it("pointer naming an unknown mode enters work even while timed and unexpired", function()
    local pointer = { mode = "retired-mode", ["until"] = "2999-01-01T00:00:00Z" }
    local action, mode = boot.decide(pointer, KNOWN_MODES, not_expired)
    t.eq("enter_work", action)
    t.eq("work", mode)
  end)

  t.it("open-ended pointer (no `until`) enters work regardless of mode named", function()
    local action, mode = boot.decide({ mode = "neutral" }, KNOWN_MODES, not_expired)
    t.eq("enter_work", action)
    t.eq("work", mode)
  end)
end)
