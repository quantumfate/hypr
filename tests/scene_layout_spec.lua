--- Scene geometry: where the tiles go.
---
--- Pure arithmetic, so these are plain tables — no compositor, no timers, no
--- dispatch. The engine this replaced could only be tested against a fake
--- Hyprland, which is why its geometry bugs were found by living with them.
local t = require("tests.harness")

_G.config = { host = { workspaces = { scenes = {} } } }

local function scene(blocks, over)
  package.loaded["hypr.scene.spec"] = nil
  package.loaded["hypr.scene.layout"] = nil
  over = over or {}
  _G.config = {
    host = {
      workspaces = {
        scenes = {
          { default_name = "code", blocks = blocks, strays = over.strays },
        },
      },
    },
  }
  local spec = require("hypr.scene.spec").load().code
  return spec, require("hypr.scene.layout")
end

local AREA = { x = 0, y = 0, w = 1000, h = 1000 }
local NO_GAPS = { gaps_in = 0, gaps_out = 0, solo_frame = false }

local function tile(address, class, group)
  return { address = address, class = class, group = group }
end

---"address:x+w" per box, so position and width are both visible in a failure.
local function trace(boxes)
  local out = {}
  for i, b in ipairs(boxes) do
    out[i] = ("%s:%d+%d"):format(b.address, b.x, b.w)
  end
  return table.concat(out, " ")
end

local TERMINALS = { classes = { "Kitty-Main" }, group = true, order = 1, share = 0.67 }
local BROWSER = { classes = { "zen-twilight" }, order = 2, share = 0.33 }

t.describe("declared blocks", function()
  t.it("takes its share of the area", function()
    local spec, layout = scene({ TERMINALS, BROWSER })
    local boxes = layout.boxes(spec, { tile("0x1", "Kitty-Main"), tile("0x9", "zen-twilight") }, AREA, NO_GAPS)
    t.eq("0x1:0+670 0x9:670+330", trace(boxes))
  end)

  t.it("places blocks in declared order regardless of arrival order", function()
    -- Ordering is the order boxes are placed. There is no correction, so a
    -- block cannot travel the wrong way and nothing can leave the monitor.
    local spec, layout = scene({ TERMINALS, BROWSER })
    local boxes = layout.boxes(spec, { tile("0x9", "zen-twilight"), tile("0x1", "Kitty-Main") }, AREA, NO_GAPS)
    t.eq("0x1:0+670 0x9:670+330", trace(boxes))
  end)

  t.it("fills the area when only one block is open", function()
    -- A 0.67 block alone must not shrink to two thirds of the panel and leave
    -- a third as wallpaper it never asked for.
    local spec, layout = scene({ TERMINALS, BROWSER })
    local boxes = layout.boxes(spec, { tile("0x1", "Kitty-Main") }, AREA, NO_GAPS)
    t.eq("0x1:0+1000", trace(boxes))
  end)

  t.it("gives a whole block one slot however many windows it holds", function()
    local spec, layout = scene({ TERMINALS, BROWSER })
    local tiles = {
      tile("0x1", "Kitty-Main", "g"),
      tile("0x2", "Kitty-Main", "g"),
      tile("0x9", "zen-twilight"),
    }
    local boxes = layout.boxes(spec, tiles, AREA, NO_GAPS)
    t.eq("0x1:0+670 0x2:0+670 0x9:670+330", trace(boxes), "group members share one box")
  end)
end)

t.describe("strays", function()
  t.it("divide what the declared blocks leave", function()
    -- The desk adjusts to what is present, and the declared ratio does not
    -- drift every time something unrelated opens.
    local spec, layout = scene({ TERMINALS })
    local boxes = layout.boxes(spec, { tile("0x1", "Kitty-Main"), tile("0xf", "mpv") }, AREA, NO_GAPS)
    t.eq("0x1:0+670 0xf:670+330", trace(boxes))
  end)

  t.it("share the remainder between them", function()
    local spec, layout = scene({ TERMINALS })
    local tiles = { tile("0x1", "Kitty-Main"), tile("0xf", "mpv"), tile("0xg", "nautilus") }
    local boxes = layout.boxes(spec, tiles, AREA, NO_GAPS)
    t.eq("0x1:0+670 0xf:670+165 0xg:835+165", trace(boxes))
  end)

  t.it("sit after the declared blocks, in arrival order", function()
    local spec, layout = scene({ TERMINALS, BROWSER })
    local tiles = { tile("0xf", "mpv"), tile("0x1", "Kitty-Main"), tile("0x9", "zen-twilight") }
    local boxes = layout.boxes(spec, tiles, AREA, NO_GAPS)
    t.ok(trace(boxes):match("^0x1:0"), "a stray never displaces a declared block: " .. trace(boxes))
  end)

  t.it("renormalise when the declaration already fills the area", function()
    -- Declared shares summing to 1 plus a stray would otherwise give the stray
    -- nothing, or a negative width.
    local spec, layout = scene({ TERMINALS, BROWSER })
    local tiles = { tile("0x1", "Kitty-Main"), tile("0x9", "zen-twilight"), tile("0xf", "mpv") }
    local boxes = layout.boxes(spec, tiles, AREA, NO_GAPS)
    for _, b in ipairs(boxes) do
      t.ok(b.w > 0, "every tile gets a positive width: " .. trace(boxes))
    end
  end)

  t.it("are floated instead when the scene asks for it", function()
    -- A scene whose geometry is a capture region keeps its split fixed.
    local spec, layout = scene({ TERMINALS }, { strays = "float" })
    t.ok(layout.floats_strays(spec))
  end)

  t.it("slot by default", function()
    local spec, layout = scene({ TERMINALS })
    t.ok(not layout.floats_strays(spec))
  end)
end)

t.describe("gaps", function()
  t.it("insets the tiles from the screen edge", function()
    local spec, layout = scene({ TERMINALS, BROWSER })
    local boxes = layout.boxes(spec, { tile("0x1", "Kitty-Main"), tile("0x9", "zen-twilight") }, AREA, {
      gaps_in = 0,
      gaps_out = 40,
      solo_frame = false,
    })
    t.eq(40, boxes[1].x)
    t.eq(920, boxes[1].w + boxes[2].w, "the pair fills the inset area exactly")
    t.eq(960, boxes[2].x + boxes[2].w, "the right edge is inset too")
  end)

  t.it("separates the tiles from each other", function()
    local spec, layout = scene({ TERMINALS, BROWSER })
    local boxes = layout.boxes(spec, { tile("0x1", "Kitty-Main"), tile("0x9", "zen-twilight") }, AREA, {
      gaps_in = 12,
      gaps_out = 0,
      solo_frame = false,
    })
    t.eq(12, boxes[2].x - (boxes[1].x + boxes[1].w))
  end)

  t.it("frames a lone tile more widely", function()
    -- What an event layer used to do by rewriting a workspace rule's gaps and
    -- restoring them later, which is why they flipped as the tile count changed.
    local spec, layout = scene({ TERMINALS })
    local boxes = layout.boxes(spec, { tile("0x1", "Kitty-Main") }, AREA, {
      gaps_in = 0,
      gaps_out = 20,
      solo_extra = 100,
    })
    t.eq(120, boxes[1].x)
    t.eq(760, boxes[1].w)
  end)

  t.it("frames a lone group like a lone window", function()
    -- A group is one node in the layout, so a workspace holding only the group
    -- deserves the same framing as one holding a single window.
    local spec, layout = scene({ TERMINALS })
    local tiles = { tile("0x1", "Kitty-Main", "g"), tile("0x2", "Kitty-Main", "g") }
    local boxes = layout.boxes(spec, tiles, AREA, { gaps_in = 0, gaps_out = 20, solo_extra = 100 })
    t.eq(120, boxes[1].x)
    t.eq(120, boxes[2].x)
  end)

  t.it("stops framing as soon as a second tile arrives", function()
    local spec, layout = scene({ TERMINALS, BROWSER })
    local tiles = { tile("0x1", "Kitty-Main"), tile("0x9", "zen-twilight") }
    local boxes = layout.boxes(spec, tiles, AREA, { gaps_in = 0, gaps_out = 20, solo_extra = 100 })
    t.eq(20, boxes[1].x)
  end)

  t.it("honours a scene that opts out of solo framing", function()
    local spec, layout = scene({ TERMINALS })
    local boxes = layout.boxes(spec, { tile("0x1", "Kitty-Main") }, AREA, {
      gaps_in = 0,
      gaps_out = 20,
      solo_extra = 100,
      solo_frame = false,
    })
    t.eq(20, boxes[1].x)
  end)
end)

t.describe("edges", function()
  t.it("places nothing on an empty workspace", function()
    local spec, layout = scene({ TERMINALS, BROWSER })
    t.eq(0, #layout.boxes(spec, {}, AREA, NO_GAPS))
  end)

  t.it("leaves no seam against the right edge", function()
    -- Rounding three shares independently loses a pixel; the last slot takes
    -- what remains instead.
    local spec, layout = scene({ TERMINALS })
    local tiles = { tile("0x1", "Kitty-Main"), tile("0xf", "mpv"), tile("0xg", "imv") }
    local boxes = layout.boxes(spec, tiles, { x = 0, y = 0, w = 999, h = 1000 }, NO_GAPS)
    local last = boxes[#boxes]
    t.eq(999, last.x + last.w)
  end)

  t.it("respects a non-zero area origin", function()
    local spec, layout = scene({ TERMINALS })
    local boxes = layout.boxes(spec, { tile("0x1", "Kitty-Main") }, { x = 100, y = 50, w = 800, h = 600 }, NO_GAPS)
    t.eq("0x1:100+800", trace(boxes))
    t.eq(50, boxes[1].y)
    t.eq(600, boxes[1].h)
  end)
end)
