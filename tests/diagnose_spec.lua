-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- Specs for hypr.lib.diagnose (LEO-213): the window-placement diagnosis
--- (PCRE-subset matcher, rule evaluation, report builder) and the diag service
--- that wraps it into the "shell/x" bind.
local t = require("tests.harness")

local M = require("hypr.lib.diagnose")
local diag = require("hypr.services.diag")

---@param s string
---@param needle string
---@return integer
local function count(s, needle)
  local n, from = 0, 1
  while true do
    local a, b = s:find(needle, from, true)
    if not a then
      return n
    end
    n, from = n + 1, b + 1
  end
end

t.describe("diagnose matcher (LEO-213)", function()
  t.it("matches literals unanchored (Hyprland search semantics)", function()
    t.ok(M.match("ab", "xxabyy"), "substring hit")
    t.ok(not M.match("ab", "xxayy"), "no hit")
    t.ok(M.match("", "anything"), "empty pattern")
  end)

  t.it("honours ^ and $ anchors", function()
    local p = "^(org[.]wezfurlong[.]wezterm)$"
    t.ok(M.match(p, "org.wezfurlong.wezterm"))
    t.ok(not M.match(p, "xorg.wezfurlong.wezterm"), "leading char")
    t.ok(not M.match(p, "org.wezfurlong.weztermX"), "trailing char")
    t.ok(M.match("^(org[.]gnome[.])", "org.gnome.Nautilus"), "anchored prefix")
    local skip = string.char(92)
    t.ok(
      M.match("^(org" .. skip .. ".wezfurlong" .. skip .. ".wezterm)$", "org.wezfurlong.wezterm"),
      "escaped-dot path"
    )
  end)

  t.it("handles alternation groups", function()
    t.ok(M.match("(vesktop|whatsapp-electron|signal)", "vesktop"))
    t.ok(M.match("(vesktop|whatsapp-electron|signal)", "whatsapp-electron"))
    t.ok(M.match("(vesktop|whatsapp-electron|signal)", "signal"))
    t.ok(M.match("(vesktop|whatsapp-electron|signal)", "signal desktop"), "substring hit")
    t.ok(not M.match("(vesktop|whatsapp-electron|signal)", "slack"))
    t.ok(M.match("([fF]irefox|zen|zen-twilight|zen-beta)", "zen-browser"), "===zen prefix===")
    t.ok(not M.match("([fF]irefox|zen|zen-twilight|zen-beta)", "Zen"), "case-sensitive")
  end)

  t.it("handles \\d and quantifiers", function()
    t.ok(M.match("steam_app_\\d+", "steam_app_1234"))
    t.ok(not M.match("steam_app_\\d+", "steam_app_default"))
    t.ok(M.match("(steam_app_default)", "steam_app_default"))
    t.ok(M.match(".*", "anything"))
    t.ok(M.match(".*", ""))
  end)

  t.it("handles character classes", function()
    t.ok(M.match("[Pp]icture", "Picture-in-Picture"), "upper P")
    t.ok(M.match("[Pp]icture", "picture"), "lower p")
    t.ok(not M.match("[Pp]icture", "xicture"))
    t.ok(not M.match("[^(Zenimax Online Studios Launcher)]", "Zenimax Online Studios Launcher"), "every char negated")
    t.ok(M.match("[^(Zenimax Online Studios Launcher)]", "Zenimax!"), "a char outside the set")
  end)

  t.it("handles dot-plus-question and star patterns", function()
    t.ok(M.match("(Picture.?in.?[Pp]icture)", "Picture-in-Picture"), "dashes")
    t.ok(M.match("(Picture.?in.?[Pp]icture)", "Picture in Picture"), "spaces")
    t.ok(M.match("(Open.*Files?|Save.*Files?|Save.*As|All Files|Save)", "Open Users Files"), "star + optional s")
    t.ok(M.match("(Open.*Files?|Save.*Files?|Save.*As|All Files|Save)", "Save As"), "star + As")
    t.ok(M.match("(Open.*Files?|Save.*Files?|Save.*As|All Files|Save)", "Save"), "bare branch")
    t.ok(M.match("(Open.*Files?|Save.*Files?|Save.*As|All Files|Save)", "Save Files"))
  end)
end)

t.describe("diagnose rule evaluation (LEO-213)", function()
  t.it("needs a match block", function()
    t.ok(not M.matches({}, { class = "x" }), "rule without match never claims")
  end)

  t.it("keys on the right window fields", function()
    local code = { match = { class = "^(code)$" } }
    t.ok(M.matches(code, { class = "code", initial_class = "code" }))
    t.ok(not M.matches(code, { class = "c0de", initial_class = "c0de" }))
    local comms = { match = { initial_class = "(vesktop|signal)" } }
    t.ok(M.matches(comms, { class = "vesktop", initial_class = "vesktop" }))
    t.ok(
      not M.matches(comms, { class = "vesktop", initial_class = "org.wezfurlong.wezterm" }),
      "===missed initialClass==="
    )
  end)

  t.it("honours tag and xwayland match fields", function()
    local tagged = { match = { tag = "default-browser" } }
    t.ok(M.matches(tagged, { tags = { "default-browser" } }))
    t.ok(M.matches(tagged, { tags = "default-browser" }), "single-string tags")
    t.ok(not M.matches(tagged, { tags = { "media-browser" } }))
    local x = { match = { xwayland = false } }
    t.ok(M.matches(x, { xwayland = false }))
    t.ok(not M.matches(x, { xwayland = true }))
  end)

  t.it("attach wraps hl.window_rule and still registers", function()
    local before = #M.rules
    M.attach()
    hl.window_rule({ match = { class = "wrapped" }, workspace = "name:code" })
    t.eq(before + 1, #M.rules, "attach records the wrapped call")
    t.eq("wrapped", hl.window_rules[#hl.window_rules].match.class, "real registration still runs")
  end)
end)

t.describe("diagnose report (LEO-213)", function()
  t.it("flags OK, MISMATCH, missing claims, and class changes", function()
    local rules = {
      { name = "comms", match = { initial_class = "(vesktop|whatsapp-electron|signal)" }, workspace = "special:comms" },
      { name = "code", match = { class = "^(code)$" }, workspace = "name:code" },
      { name = "steam", match = { class = "steam_app_\\d+" }, workspace = 3 },
      { name = "browse", match = { class = "(zen|zen-twilight|zen-beta)" }, workspace = "name:browse" },
    }
    local windows = {
      { class = "code", initial_class = "code", title = "editor", workspace = { id = 2, name = "code" } },
      { class = "vesktop", initial_class = "vesktop", title = "discord", workspace = { id = -4, name = "comms" } },
      {
        class = "steam_app_25663",
        initial_class = "steam_app_25663",
        title = "game",
        workspace = { id = 3, name = "3" },
      },
      { class = "zen", initial_class = "zen", title = "browser", workspace = { id = 9, name = "other" } },
      {
        class = "vesktop",
        initial_class = "org.gnome.Nautilus",
        title = "late rebrand",
        workspace = { id = -4, name = "comms" },
      },
    }
    local r = M.report(windows, rules)
    t.ok(r:find("via class", 1, true) ~= nil, "class field hit")
    t.ok(r:find("via initialClass", 1, true) ~= nil, "initialClass field hit")
    t.eq(3, count(r, "verdict: OK"), "windows 1..3 on their claimed workspace")
    t.ok(r:find("verdict: MISMATCH — expected name:browse", 1, true) ~= nil, "window 4 landed elsewhere")
    t.ok(r:find("verdict: no workspace rule claims this window", 1, true) ~= nil, "window 5 matched nothing")
    t.ok(
      r:find("note:    class changed since map (org.gnome.Nautilus -> vesktop)", 1, true) ~= nil,
      "initial-class divergence surfaced"
    )
    t.ok(r:find("5 windows, 4 rules, 1 mismatched", 1, true) ~= nil, "summary")
  end)
end)

t.describe("diag service (LEO-213)", function()
  t.it("writes the report and raises a notification", function()
    M.record({ match = { class = "^(code)$" }, workspace = "name:code" })
    hl.get_windows = function()
      return { { class = "code", initial_class = "code", title = "editor", workspace = { id = 2, name = "code" } } }
    end
    diag.run()
    t.ok(hl.exec_cmds[#hl.exec_cmds]:find("^notify%-send 'Window placement' ", 1), "notify-send raised")
    local path = diag.write_report("report body")
    local f = assert(io.open(path, "r"))
    local body = f:read("*a")
    f:close()
    os.remove(path)
    t.ok(body:find("report body", 1, true) ~= nil, "file written")
  end)
end)
