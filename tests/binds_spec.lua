-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
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
  shelves = {
    { name = "signal", key = "s", class = "signal", cmd = "signal-desktop", desc = "Signal" },
    { name = "steam", key = "t", class = "steam", cmd = "steam", desc = "Steam", tree = "shelf-steam" },
  },
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

t.describe("the shell submap (LEO-346)", function()
  --- The dofus/ankama widget key belongs to the dofus scene's own tree
  --- (`SUPER Space d`), never leaked into the generic shell submap
  --- (`SUPER Space q`) — a scene-worthy abstraction owns its bindings
  --- (AGENTS.md).
  t.it("holds no dofus-related key", function()
    local leaked = {}
    for _, b in ipairs(hl.binds) do
      if b.submap == "shell" and b.opts and b.opts.description then
        if b.opts.description:lower():match("dofus") or b.opts.description:lower():match("ankama") then
          leaked[#leaked + 1] = b.opts.description
        end
      end
    end
    t.eq({}, leaked, "the shell submap carries a dofus/ankama key")
  end)
end)

t.describe("the modes tree", function()
  --- Entering a mode is the one action that drives both halves of the desk, so
  --- the keys that reach it are worth pinning: a mode with no key is a mode
  --- that exists only in a file.
  t.it("carries one entry per declared mode", function()
    local entries = {}
    for _, b in ipairs(hl.binds) do
      if b.submap == "modes" and b.key and not b.key:match("escape") then
        entries[#entries + 1] = b.key
      end
    end
    -- The stub has no declaration, so the tree shows the seed hint rather than
    -- an empty submap that would look like the feature is broken.
    t.ok(#entries >= 1, "the modes tree is empty")
  end)

  t.it("is reachable from a leader key of its own", function()
    local found = false
    for _, b in ipairs(hl.binds) do
      if b.submap == "" and b.key == "+SUPER+f+" then
        found = true
      end
    end
    t.ok(found, "no root-level entry into the modes tree")
  end)
end)

t.describe("the way out of a mode", function()
  --- A mode withholds things, so the failure that matters is a desk you cannot
  --- get back from. This bind exists because that failure once cost a reboot.
  t.it("is bound at root, where no mode can withhold it", function()
    local found
    for _, b in ipairs(hl.binds) do
      if b.opts and b.opts.description == "Modes: return to neutral" then
        found = b
      end
    end
    t.ok(found, "no escape back to neutral")
    t.eq("", found.submap, "the escape is inside a submap something could remove")
  end)

  t.it("works from inside any submap", function()
    -- Being half-way through a key sequence when you realise you are stuck
    -- should not be the thing that stops you getting out.
    local found
    for _, b in ipairs(hl.binds) do
      if b.opts and b.opts.description == "Modes: return to neutral" then
        found = b
      end
    end
    t.eq(true, found.opts.submap_universal)
  end)
end)

t.describe("key strings", function()
  --- A bind Hyprland cannot parse does not fail quietly: it raises at config
  --- load and takes down every module required after it, so the desk comes up
  --- with no binds and no workspace rules. That has happened twice.
  t.it("never use a comma to separate the key from its modifiers", function()
    -- `parse_mods` returns "+SUPER+CTRL+" and the key belongs inside that
    -- list. Appending ", escape" produced "+SUPER+CTRL+SHIFT+, escape", which
    -- Hyprland rejects as an unknown key.
    local bad = {}
    for _, b in ipairs(hl.binds) do
      if type(b.key) == "string" and b.key:find(", ") then
        bad[#bad + 1] = b.key
      end
    end
    t.eq({}, bad, "a key string separates its key with a comma")
  end)

  t.it("never end with a dangling separator", function()
    -- "+SUPER+ALT+ + " would bind no key at all.
    local bad = {}
    for _, b in ipairs(hl.binds) do
      if type(b.key) == "string" and (b.key:match("%+%s*$") and b.key:match("%+%s*%+%s*$")) then
        bad[#bad + 1] = b.key
      end
    end
    t.eq({}, bad, "a key string ends without naming a key")
  end)
end)
