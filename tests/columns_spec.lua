-- hypr/scene/columns.lua: fitting a scene's declared roles into a
-- monitor's available width, per docs/columns.md §1-§3.
--
-- DISCREPANCY (reported, not silently corrected -- see the issue comment):
-- docs/columns.md §4's own "Worked outcomes" tables do not reconcile
-- against §4's own canonical inputs table. That opening table states
-- gaps_in = 60/48/40 for DP-1/DP-2/Laptop and available_width = 4960/2432/
-- 1824 (5120-80*2, 2560-64*2, 1920-48*2 -- the doc's own formula). Re-running
-- every worked table's numbers backwards shows they were actually computed
-- with gaps_in = 12/6/4 and, for DP-2 and Laptop, available_width = 2532/
-- 1904 instead -- e.g. dofus DP-1's own text says "cost of two
-- (3400+480+12=3892)", twelve, not the profile's sixty; dofus DP-2's
-- degenerate clamp is stated as 2532px, which is not even equal to that
-- table's own stated W of 2432px. The pattern is exact and uniform across
-- all eight scenes (every single-flex-column outcome below reproduces to
-- the pixel once gaps_in is read as 12/6/4 and DP-2/Laptop's W as
-- 2532/1904), so this is not scene-specific noise -- §4 was computed
-- against stale numbers, not the profile table two paragraphs above it.
--
-- These specs pin the CORRECT arithmetic: docs/columns.md §1-§3's resolver
-- contract applied to §4's own canonical inputs table (gaps_in 60/48/40,
-- available_width 4960/2432/1824). Follow-up: reconcile or correct §4.
local t = require("tests.harness")
local columns = require("hypr.scene.columns")

---"priority:width+x_offset[members]" per column, so every field a spec
---might disagree about shows up in one failure message.
---@param resolved table[]
---@return string
local function trace(resolved)
  local out = {}
  for i, c in ipairs(resolved) do
    out[i] = ("%d:%d+%d[%s]"):format(c.priority, c.width, c.x_offset, table.concat(c.members, ","))
  end
  return table.concat(out, " ")
end

-- profile: { available_width, gaps_in }
local DP1 = { 4960, 60 }
local DP2 = { 2432, 48 }
local LAPTOP = { 1824, 40 }

local function resolve(roles, profile)
  return columns.resolve(roles, profile[1], profile[2])
end

t.describe("docs/columns.md §4 worked outcomes (all eight scenes, all three profiles)", function()
  t.describe("dofus (1 fixed_width=3400 align=left, 2 min_width=480)", function()
    local roles =
      { { priority = 1, min_width = 3400, fixed_width = 3400, align = "left" }, { priority = 2, min_width = 480 } }
    t.it("DP-1: two columns, slack to the flexible companion", function()
      t.eq("1:3400+0[1] 2:1500+0[2]", trace(resolve(roles, DP1)))
    end)
    t.it("DP-2: degenerate clamp -- fixed group alone still exceeds W", function()
      t.eq("1:2432+0[1,2]", trace(resolve(roles, DP2)))
    end)
    t.it("Laptop: degenerate clamp, same shape as DP-2", function()
      t.eq("1:1824+0[1,2]", trace(resolve(roles, LAPTOP)))
    end)
  end)

  t.describe("pokemon (1 min_width=700, 2 min_width=600, 3 min_width=600)", function()
    local roles =
      { { priority = 1, min_width = 700 }, { priority = 2, min_width = 600 }, { priority = 3, min_width = 600 } }
    t.it("DP-1: three columns, no fold", function()
      t.eq("1:3640+0[1] 2:600+0[2] 3:600+0[3]", trace(resolve(roles, DP1)))
    end)
    t.it("DP-2: three columns, no fold", function()
      t.eq("1:1136+0[1] 2:600+0[2] 3:600+0[3]", trace(resolve(roles, DP2)))
    end)
    t.it("Laptop: stream folds into chat by priority (no fold_into declared)", function()
      t.eq("1:1184+0[1] 2:600+0[2,3]", trace(resolve(roles, LAPTOP)))
    end)
  end)

  t.describe("steam-games / media (1 min_width=800, always fills W)", function()
    local roles = { { priority = 1, min_width = 800 } }
    t.it("DP-1", function()
      t.eq("1:4960+0[1]", trace(resolve(roles, DP1)))
    end)
    t.it("DP-2", function()
      t.eq("1:2432+0[1]", trace(resolve(roles, DP2)))
    end)
    t.it("Laptop", function()
      t.eq("1:1824+0[1]", trace(resolve(roles, LAPTOP)))
    end)
  end)

  t.describe("code (1 editor min_width=1200, 2 browser min_width=800)", function()
    local roles = { { priority = 1, min_width = 1200 }, { priority = 2, min_width = 800 } }
    t.it("DP-1: no fold, slack to editor", function()
      t.eq("1:4100+0[1] 2:800+0[2]", trace(resolve(roles, DP1)))
    end)
    t.it("DP-2: no fold, slack to editor", function()
      t.eq("1:1584+0[1] 2:800+0[2]", trace(resolve(roles, DP2)))
    end)
    t.it("Laptop: browser folds into editor, which then fills the panel", function()
      t.eq("1:1824+0[1,2]", trace(resolve(roles, LAPTOP)))
    end)
  end)

  t.describe("obsidian-linear (1 min_width=900, 2 min_width=700)", function()
    local roles = { { priority = 1, min_width = 900 }, { priority = 2, min_width = 700 } }
    t.it("DP-1", function()
      t.eq("1:4200+0[1] 2:700+0[2]", trace(resolve(roles, DP1)))
    end)
    t.it("DP-2", function()
      t.eq("1:1684+0[1] 2:700+0[2]", trace(resolve(roles, DP2)))
    end)
    t.it("Laptop: deliberately does not fold -- two panes still fit", function()
      t.eq("1:1084+0[1] 2:700+0[2]", trace(resolve(roles, LAPTOP)))
    end)
  end)

  t.describe("proton (1 min_width=700, 2 min_width=420)", function()
    local roles = { { priority = 1, min_width = 700 }, { priority = 2, min_width = 420 } }
    t.it("DP-1", function()
      t.eq("1:4480+0[1] 2:420+0[2]", trace(resolve(roles, DP1)))
    end)
    t.it("DP-2", function()
      t.eq("1:1964+0[1] 2:420+0[2]", trace(resolve(roles, DP2)))
    end)
    t.it("Laptop: never folds, both columns comfortably narrow", function()
      t.eq("1:1364+0[1] 2:420+0[2]", trace(resolve(roles, LAPTOP)))
    end)
  end)

  t.describe("logs (no blocks declared)", function()
    t.it("no roles resolves to no columns -- the caller treats that as one implicit full-width column", function()
      t.eq({}, columns.resolve({}, DP1[1], DP1[2]))
    end)
  end)
end)

t.describe("fixed_width", function()
  t.it("at its number: fits exactly, no clamp", function()
    local roles = { { priority = 1, min_width = 500, fixed_width = 500 } }
    t.eq("1:500+0[1]", trace(columns.resolve(roles, 500, 0)))
  end)

  t.it("below its number: the degenerate clamp overrides it even though it is fixed", function()
    local roles = { { priority = 1, min_width = 500, fixed_width = 500 } }
    t.eq("1:400+0[1]", trace(columns.resolve(roles, 400, 0)))
  end)

  t.it("never grows past its declared number even at the highest priority", function()
    local roles = { { priority = 1, min_width = 300, fixed_width = 300 }, { priority = 2, min_width = 300 } }
    -- Slack must go to the flexible role 2, not stretch the fixed role 1.
    t.eq("1:300+0[1] 2:700+0[2]", trace(columns.resolve(roles, 1010, 10)))
  end)
end)

t.describe("align (all surviving columns fixed-width, leftover unclaimed by any column)", function()
  local function two_fixed(align)
    return {
      { priority = 1, min_width = 100, fixed_width = 100, align = align },
      { priority = 2, min_width = 100, fixed_width = 100 },
    }
  end

  t.it("left (default): row packs against the leading edge, leftover trails", function()
    t.eq("1:100+0[1] 2:100+0[2]", trace(columns.resolve(two_fixed("left"), 300, 10)))
  end)

  t.it("right: row packs against the trailing edge, leftover leads", function()
    t.eq("1:100+90[1] 2:100+90[2]", trace(columns.resolve(two_fixed("right"), 300, 10)))
  end)

  t.it("center: leftover splits evenly on both sides", function()
    t.eq("1:100+45[1] 2:100+45[2]", trace(columns.resolve(two_fixed("center"), 300, 10)))
  end)

  t.it("has no visible effect once any surviving column is flexible", function()
    local roles =
      { { priority = 1, min_width = 100, fixed_width = 100, align = "right" }, { priority = 2, min_width = 100 } }
    t.eq("1:100+0[1] 2:200+0[2]", trace(columns.resolve(roles, 300, 0)))
  end)
end)

t.describe("folding", function()
  t.it("by priority: the lowest-priority survivor folds into the next one up, absent fold_into", function()
    local roles =
      { { priority = 1, min_width = 100 }, { priority = 2, min_width = 100 }, { priority = 3, min_width = 100 } }
    t.eq("1:100+0[1] 2:100+0[2,3]", trace(columns.resolve(roles, 210, 10)))
  end)

  t.it("via explicit fold_into: a named target, not the priority-adjacent one", function()
    local roles = {
      { priority = 1, min_width = 100 },
      { priority = 2, min_width = 100 },
      { priority = 3, min_width = 100, fold_into = 1 },
    }
    t.eq("1:100+0[1,3] 2:100+0[2]", trace(columns.resolve(roles, 210, 10)))
  end)

  t.it("cascades: folding the new lowest survivor carries its already-folded members along", function()
    local roles = {
      { priority = 1, min_width = 100 },
      { priority = 2, min_width = 100 },
      { priority = 3, min_width = 100 },
      { priority = 4, min_width = 100 },
    }
    -- 4 columns of 100 with gaps 10 cost 430; each fold drops one column and
    -- one gap (100+10=110) until the remainder fits.
    t.eq("1:100+0[1] 2:100+0[2,3,4]", trace(columns.resolve(roles, 210, 10)))
  end)

  t.it("a fold_into naming an already-folded-away role still lands where that role now lives", function()
    local roles = {
      { priority = 1, min_width = 100 },
      { priority = 2, min_width = 100 },
      { priority = 3, min_width = 100 },
      -- Names role 2, which itself folds into role 1 before role 4 is
      -- considered (both fold passes are needed to fit 210).
      { priority = 4, min_width = 100, fold_into = 2 },
    }
    t.eq("1:100+0[1] 2:100+0[2,4,3]", trace(columns.resolve(roles, 210, 10)))
  end)

  t.it("a mis-declared self-fold falls back to the next one up", function()
    local roles = { { priority = 1, min_width = 100 }, { priority = 2, min_width = 100, fold_into = 2 } }
    t.eq("1:100+0[1,2]", trace(columns.resolve(roles, 100, 10)))
  end)
end)

t.describe("degenerate case (§3): even the sole surviving column is under its own effective width", function()
  t.it("a min_width role alone gets the whole of a narrower available_width", function()
    local roles = { { priority = 1, min_width = 500 } }
    t.eq("1:300+0[1]", trace(columns.resolve(roles, 300, 0)))
  end)

  t.it("folds all the way to one column, then still clamps", function()
    local roles = { { priority = 1, min_width = 1000 }, { priority = 2, min_width = 1000 } }
    t.eq("1:300+0[1,2]", trace(columns.resolve(roles, 300, 10)))
  end)
end)
