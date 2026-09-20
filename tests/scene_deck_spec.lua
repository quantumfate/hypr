---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- Deck geometry: which window a column shows, column widths, scroll
--- clamping, group collapse, the 1-3 column bound, and per-scene opt-out.
--- Plain arithmetic, no compositor — mirrors tests/scene_layout_spec.lua.
local t = require("tests.harness")
local deck = require("hypr.scene.deck")

local AREA = { x = 0, y = 0, w = 900, h = 600 }
local NO_GAPS = { gaps_in = 0, gaps_out = 0 }

local function tile(address, class, tags, group)
  return { address = address, class = class, tags = tags, group = group }
end

---The boxes that landed inside the work area, and the ones parked off it.
---A hidden member is placed a full column height beyond an edge (LEO-402),
---so "visible" is simply "its box overlaps the area vertically".
---@param boxes Scene.Box[]
---@return Scene.Box[] visible, string[] offscreen addresses
local function split(boxes)
  local visible, offscreen = {}, {}
  for _, box in ipairs(boxes) do
    if box.y >= AREA.y and box.y + box.h <= AREA.y + AREA.h then
      visible[#visible + 1] = box
    else
      offscreen[#offscreen + 1] = box.address
    end
  end
  return visible, offscreen
end

t.describe("applies", function()
  t.it("opts in only with layout = deck", function()
    t.eq(true, deck.applies({ layout = "deck" }))
    t.eq(false, deck.applies({ layout = "scene" }))
    t.eq(false, deck.applies({}))
    t.eq(false, deck.applies(nil))
  end)
end)

t.describe("column_for", function()
  local spec = {
    columns = {
      { order = 1, classes = { "Kitty%-Main", "Proj%-.*" } },
      { order = 2, classes = { "md.obsidian.Obsidian" }, deck = "notes" },
    },
  }

  t.it("matches by class", function()
    local c = deck.column_for(spec, tile("0x1", "Kitty%-Main"))
    t.eq(1, c and c.order)
  end)

  t.it("matches by self-declared deck tag regardless of class", function()
    local c = deck.column_for(spec, tile("0x1", "linear", { "deck:notes" }))
    t.eq(2, c and c.order)
  end)

  t.it("returns nil for an unclaimed class", function()
    t.eq(nil, deck.column_for(spec, tile("0x1", "steam")))
  end)
end)

t.describe("boxes: column widths", function()
  t.it("splits declared shares like scene blocks", function()
    local spec = {
      columns = {
        { order = 1, share = 0.6, classes = { "A" } },
        { order = 2, share = 0.4, classes = { "B" } },
      },
    }
    local boxes = deck.boxes(spec, { tile("a", "A"), tile("b", "B") }, AREA, NO_GAPS)
    local by = {}
    for _, box in ipairs(boxes) do
      by[box.address] = box
    end
    t.eq(540, by.a.w)
    t.eq(360, by.b.w)
    t.eq(540, by.b.x)
  end)

  t.it("splits evenly with no declared shares", function()
    local spec = {
      columns = {
        { order = 1, classes = { "A" } },
        { order = 2, classes = { "B" } },
        { order = 3, classes = { "C" } },
      },
    }
    local boxes = deck.boxes(spec, { tile("a", "A"), tile("b", "B"), tile("c", "C") }, AREA, NO_GAPS)
    local by = {}
    for _, box in ipairs(boxes) do
      by[box.address] = box
    end
    t.eq(300, by.a.w)
    t.eq(300, by.b.w)
    t.eq(300, by.c.w)
  end)
end)

t.describe("boxes: which window shows", function()
  local spec = { columns = { { order = 1, share = 1, classes = { "Kitty%-Main" } } } }

  t.it("shows the first window by default (no scroll opt)", function()
    local boxes = deck.boxes(spec, { tile("a", "Kitty%-Main"), tile("b", "Kitty%-Main") }, AREA, NO_GAPS)
    local visible, offscreen = split(boxes)
    t.eq(2, #boxes, "every member is placed; none leaves the workspace")
    t.eq("a", visible[1].address)
    t.eq("b", offscreen[1])
  end)

  t.it("shows the scrolled-to window and parks the rest off-screen", function()
    local opts = { gaps_in = 0, gaps_out = 0, scroll = { [1] = 2 } }
    local boxes = deck.boxes(spec, { tile("a", "Kitty%-Main"), tile("b", "Kitty%-Main") }, AREA, opts)
    local visible, offscreen = split(boxes)
    t.eq("b", visible[1].address)
    t.eq("a", offscreen[1])
  end)

  t.it("a member before the scroll index parks above, one after it below", function()
    local opts = { gaps_in = 0, gaps_out = 0, scroll = { [1] = 2 } }
    local tiles = { tile("a", "Kitty%-Main"), tile("b", "Kitty%-Main"), tile("c", "Kitty%-Main") }
    local by = {}
    for _, box in ipairs(deck.boxes(spec, tiles, AREA, opts)) do
      by[box.address] = box
    end
    t.ok(by.a.y + by.a.h <= AREA.y, "the member before the visible one sits above the screen")
    t.ok(by.c.y >= AREA.y + AREA.h, "the member after it sits below the screen")
  end)

  t.it("fills the whole column height, never a partial split", function()
    local boxes = deck.boxes(spec, { tile("a", "Kitty%-Main"), tile("b", "Kitty%-Main") }, AREA, NO_GAPS)
    t.eq(600, split(boxes)[1].h)
  end)
end)

t.describe("boxes: scroll clamping", function()
  local spec = { columns = { { order = 1, share = 1, classes = { "A" } } } }

  t.it("clamps past the end to the last window", function()
    local opts = { gaps_in = 0, gaps_out = 0, scroll = { [1] = 99 } }
    local boxes = deck.boxes(spec, { tile("a", "A"), tile("b", "A") }, AREA, opts)
    t.eq("b", split(boxes)[1].address)
  end)

  t.it("clamps below 1 to the first window", function()
    local opts = { gaps_in = 0, gaps_out = 0, scroll = { [1] = 0 } }
    local boxes = deck.boxes(spec, { tile("a", "A"), tile("b", "A") }, AREA, opts)
    t.eq("a", split(boxes)[1].address)
  end)

  t.it("clamps to nothing for an empty column", function()
    t.eq(0, #deck.boxes(spec, {}, AREA, NO_GAPS))
  end)

  t.it("clamp_scroll is a direct pure decision", function()
    t.eq(0, deck.clamp_scroll(1, 0))
    t.eq(1, deck.clamp_scroll(nil, 3))
    t.eq(3, deck.clamp_scroll(5, 3))
    t.eq(1, deck.clamp_scroll(-2, 3))
  end)
end)

t.describe("boxes: group collapse", function()
  t.it("a group's members share one box when the group is visible", function()
    local spec = { columns = { { order = 1, share = 1, classes = { "Kitty%-Main" } } } }
    local tiles = {
      tile("a", "Kitty%-Main", nil, "grp1"),
      tile("b", "Kitty%-Main", nil, "grp1"),
    }
    local visible = split(deck.boxes(spec, tiles, AREA, NO_GAPS))
    t.eq(2, #visible)
    t.eq(visible[1].x, visible[2].x)
    t.eq(visible[1].w, visible[2].w)
  end)

  t.it("a group counts as one deck entry for scrolling", function()
    local spec = { columns = { { order = 1, share = 1, classes = { "Kitty%-Main", "zen" } } } }
    local tiles = {
      tile("a", "Kitty%-Main", nil, "grp1"),
      tile("b", "Kitty%-Main", nil, "grp1"),
      tile("c", "zen"),
    }
    local opts = { gaps_in = 0, gaps_out = 0, scroll = { [1] = 2 } }
    local visible, offscreen = split(deck.boxes(spec, tiles, AREA, opts))
    t.eq(1, #visible)
    t.eq("c", visible[1].address)
    table.sort(offscreen)
    t.eq("a", offscreen[1])
    t.eq("b", offscreen[2])
  end)
end)

t.describe("boxes: 1-3 column bound", function()
  t.it("a fourth declared column is dropped, not placed", function()
    local spec = {
      columns = {
        { order = 1, share = 0.25, classes = { "A" } },
        { order = 2, share = 0.25, classes = { "B" } },
        { order = 3, share = 0.25, classes = { "C" } },
        { order = 4, share = 0.25, classes = { "D" } },
      },
    }
    local tiles = { tile("a", "A"), tile("b", "B"), tile("c", "C"), tile("d", "D") }
    local boxes = deck.boxes(spec, tiles, AREA, NO_GAPS)
    local addresses = {}
    for _, box in ipairs(boxes) do
      addresses[box.address] = true
    end
    t.ok(addresses.a and addresses.b and addresses.c)
    t.ok(not addresses.d)
  end)

  t.it("no columns places nothing", function()
    t.eq(0, #deck.boxes({ columns = {} }, { tile("a", "A") }, AREA, NO_GAPS))
  end)
end)

t.report()
