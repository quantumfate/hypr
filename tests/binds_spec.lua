--- The highest-value spec in this suite: two entries bound to the same key
--- inside one submap are invisible until someone presses the wrong one, and
--- an undescribed bind is invisible to the cheatsheet. Both are silent until
--- this test.
local t = require("tests.harness")

-- Minimal but realistic fixture: same shape hyprland.lua builds, just without
-- a real hostname lookup. Only the fields hypr/binds.lua actually reads.
_G.config = {
  main_mod = "SUPER",
  primary_mod = "CTRL",
  secondary_mod = "SHIFT",
  tertiary_mod = "ALT",
  apps = {
    media_browser = { cmd = "zen-twilight", class = "" },
    main_browser = { cmd = "zen-twilight", class = "" },
    dev_browser = { cmd = "firefox", class = "" },
    terminal = { cmd = "kitty", class = "Kitty-Main" },
    terminal_float = { cmd = "kitty", class = "Kitty-Float" },
    volume_control = { cmd = "wiremix", class = "" },
    file_manager = { cmd = "yazi", class = "" },
    password_manager = { cmd = "proton-pass", class = "" },
    mail = { cmd = "proton-mail", class = "" },
    calculator = { cmd = "qalculate-qt", class = "" },
    app_launcher = { cmd = "rofi", class = "" },
    bluetooth_manager = { cmd = "bluetui", class = "" },
    package_manager_ui = { cmd = "shelly-ui", class = "" },
    package_manager_tui = { cmd = "parui", class = "" },
  },
  host = {
    primary_monitor = "eDP-1",
    workspaces = {
      workspace_keys = { "1", "2", "3" },
      workspace_specs = { { workspace = "1" }, { workspace = "2" }, { workspace = "3" } },
    },
  },
}

require("hypr.binds")

--- Canonical "mods+key" for a stub-recorded bind key string, so
--- "+SUPER+SHIFT+h+" and "SUPER + SHIFT + h" (submap.lua vs. bind.lua's own
--- formatting) compare equal: split on '+', trim, drop empties, uppercase,
--- sort (modifier order isn't semantic), rejoin.
---@param key string
---@return string
local function canonical_key(key)
  local parts = {}
  for raw in key:gmatch("[^+]+") do
    local part = raw:match("^%s*(.-)%s*$")
    if part ~= "" then
      parts[#parts + 1] = part:upper()
    end
  end
  table.sort(parts)
  return table.concat(parts, "+")
end

-- Escape/reset are wired into every submap by submap.lua itself (not authored
-- per-submap), always undescribed and always identical — infrastructure, not
-- a cheatsheet gap.
local function is_submap_nav(key)
  local c = canonical_key(key)
  return c == "ESCAPE" or c == "ESCAPE+SHIFT"
end

t.describe("binds (built via hypr.binds)", function()
  t.it("registered at least one bind", function()
    t.ok(#hl.binds > 0, "expected hypr.binds to register binds through the hl stub")
  end)

  t.it("no duplicate key+modifier combination within a single submap", function()
    local seen = {} -- seen[submap][canonical_key] = key (first one seen, for the message)
    local dupes = {}
    for _, b in ipairs(hl.binds) do
      if not b.unbind then
        local ck = canonical_key(b.key)
        seen[b.submap] = seen[b.submap] or {}
        if seen[b.submap][ck] then
          dupes[#dupes + 1] = ("submap %q: %q collides with %q"):format(b.submap, b.key, seen[b.submap][ck])
        else
          seen[b.submap][ck] = b.key
        end
      end
    end
    t.eq({}, dupes, "duplicate key+modifier combinations within a submap")
  end)

  t.it("no duplicate key+modifier combination at the root level", function()
    local seen = {}
    local dupes = {}
    for _, b in ipairs(hl.binds) do
      if not b.unbind and b.submap == "" then
        local ck = canonical_key(b.key)
        if seen[ck] then
          dupes[#dupes + 1] = ("%q collides with %q"):format(b.key, seen[ck])
        else
          seen[ck] = b.key
        end
      end
    end
    t.eq({}, dupes, "duplicate key+modifier combinations at the root")
  end)

  t.it("every bind carries a non-empty description", function()
    local undescribed = {}
    for _, b in ipairs(hl.binds) do
      if not b.unbind and not is_submap_nav(b.key) then
        local desc = b.opts.description
        if not desc or desc == "" then
          undescribed[#undescribed + 1] = ("submap %q: key %q has no description"):format(b.submap, b.key)
        end
      end
    end
    t.eq({}, undescribed, "binds with no cheatsheet description")
  end)
end)
