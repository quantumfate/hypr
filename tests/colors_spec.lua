-- LEO-341: the compositor's accent must re-resolve on a mode change, not
-- only at config load. `apply_colors` is the re-callable unit under test —
-- these specs assert on what it pushed through the stubbed `hl.config`
-- rather than on a live compositor.
local t = require("tests.harness")

-- store.lua reads its roots once at require-time (see store_spec.lua for the
-- same pattern): point QF_STORE at a scratch dir before requiring anything
-- under test, so a real store file drives the resolution instead of a stub.
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

_G.hl = require("tests.hl_stub").new()

local Store = require("hypr.lib.store")
local colors = require("hypr.themes.colors")

-- The theme palette macchiato/latte/etc. carries `red`; the declaration below
-- points `study` at it, matching LEO-330's four accents. `gaming`/`focus`/
-- `relax` name the three pale roles that fail the light-palette contrast
-- guard, so the guard tests below can exercise them through the same reader.
Store.define("hyprfocus"):put({
  modes = {
    study = { presentation = { accent_role = "red" } },
    work = { presentation = { accent_role = "blue" } },
    gaming = { presentation = { accent_role = "lavender" } },
    focus = { presentation = { accent_role = "peach" } },
    relax = { presentation = { accent_role = "yellow" } },
  },
})

t.describe("colors.apply_colors", function()
  t.it("resolves the mode's accent onto the compositor border/groupbar config", function()
    Store.define("focus"):put({ mode = "study" })
    local theme = colors.apply_colors("macchiato", "study")
    t.eq(theme.red, _G.hl.last_config.general.col.active_border)
    t.eq(theme.red, _G.hl.last_config.group.col.border_active)
    t.eq(theme.red, _G.hl.last_config.group.groupbar.col.active)
  end)

  t.it("is re-callable: a second mode overwrites the first mode's accent", function()
    local theme = colors.apply_colors("macchiato", "work")
    t.eq(theme.blue, _G.hl.last_config.general.col.active_border)
  end)

  t.it("defaults to the live stores when called with no arguments", function()
    Store.define("theme"):put({ palette = "macchiato" })
    Store.define("focus"):put({ mode = "study" })
    local theme = colors.apply_colors()
    t.eq(theme.red, _G.hl.last_config.general.col.active_border)
  end)

  t.describe("light-palette contrast guard", function()
    t.it("keeps the two latte roles that pass contrast", function()
      Store.define("focus"):put({ mode = "work" })
      local theme = colors.apply_colors("latte", "work")
      t.eq(theme.blue, _G.hl.last_config.general.col.active_border)
      t.eq(theme.blue, _G.hl.last_config.group.col.border_active)
    end)

    t.it("stands in mauve for every latte role that fails", function()
      for _, mode in ipairs({ "gaming", "focus", "relax" }) do
        Store.define("focus"):put({ mode = mode })
        local theme = colors.apply_colors("latte", mode)
        t.eq(
          theme.mauve,
          _G.hl.last_config.general.col.active_border,
          tostring(mode) .. "'s pale role must yield to mauve on latte"
        )
      end
    end)

    t.it("passes every role through on the dark palettes", function()
      for _, palette in ipairs({ "frappe", "macchiato", "mocha" }) do
        Store.define("focus"):put({ mode = "gaming" })
        local theme = colors.apply_colors(palette, "gaming")
        t.eq(theme.lavender, _G.hl.last_config.general.col.active_border)
        Store.define("focus"):put({ mode = "focus" })
        theme = colors.apply_colors(palette, "focus")
        t.eq(theme.peach, _G.hl.last_config.general.col.active_border)
      end
    end)
  end)
end)

-- All specs share one process (see run.lua) — restore os.getenv so later
-- specs see the real environment.
os.getenv = real_getenv
