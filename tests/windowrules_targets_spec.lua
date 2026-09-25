-- Every `workspace = "name:X"` a window rule targets must be a real scene
-- workspace (docs/scenes.md: scenes are keyed by `default_name`). A rule left
-- pointing at a renamed or retired workspace silently loses its scene — no
-- group, no split, no companion — which is exactly the regression LEO-336
-- fixed. This loads the full config, per host, the same way
-- config_smoke_spec does, and checks every recorded `hl.window_rule` call.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
local t = require("tests.harness")

---Load the real hyprland.lua for a named host, with the runtime stubbed.
---@param hostname string
---@return boolean, string?
local function load_config(hostname)
  for name in pairs(package.loaded) do
    if name == "hypr" or name:match("^hypr%.") then
      package.loaded[name] = nil
    end
  end
  _G.hl = require("tests.hl_stub").new({ readonly = true })
  _G.config = nil

  package.loaded["hypr.lib.util"] = nil
  local util = require("hypr.lib.util")
  local real = util.hostname
  util.hostname = function()
    return hostname
  end

  local ok, err = pcall(dofile, "hyprland.lua")
  util.hostname = real
  return ok, err and tostring(err) or nil
end

-- One entry per file in conf/hosts/: the two named machines, plus an
-- unmatched hostname to exercise default.lua the way conf/host.lua does.
local hosts = { "quantum-desktop", "quantum-laptop", "quantum-nowhere" }

t.describe("window rule workspace targets", function()
  for _, host in ipairs(hosts) do
    t.it("every name: target on " .. host .. " is a real workspace", function()
      local ok, err = load_config(host)
      t.ok(ok, "config failed to load: " .. tostring(err))

      local known = {}
      for _, spec in ipairs(config.host.workspaces.workspace_specs) do
        known[spec.default_name] = true
      end

      for _, rule in ipairs(hl.window_rules) do
        local target = rule.workspace
        if type(target) == "string" then
          local name = target:match("^name:(.+)$")
          if name then
            t.ok(known[name], "workspace rule targets unknown name:" .. name)
          end
        end
      end
    end)
  end
end)

t.describe("declared-group prompts (the pickers and the confirm dialog)", function()
  -- A prompt wears its group's class prefix, so every rule keyed on that
  -- prefix catches it too. Live (2026-09-24) the project picker was swallowed
  -- into a neighbouring project group and then EJECTED -- an
  -- `HL.Group:remove`, the one call that re-assigns a window's space and
  -- breaks the formation. The journal named the windows: `Proj-picker` and
  -- `Proj-confirm` on the `code` scene. Barring the class stops the swallow,
  -- so no eject is ever needed; this pins that every prompt class carries
  -- both rules, since the behaviour itself does not reproduce in the harness
  -- (the picker floats there and auto_group leaves it alone).
  t.it("are barred from every group, and take their own focus", function()
    local ok, err = load_config("quantum-desktop")
    t.ok(ok, "config failed to load: " .. tostring(err))

    for _, cls in ipairs(config.apps.declared_group_prompts) do
      local barred, focused = false, false
      for _, rule in ipairs(hl.window_rules) do
        local match = rule.match or {}
        if match.class == cls and rule.group == "barred" then
          barred = true
        end
        if match.initial_class == cls and rule.no_initial_focus == false then
          focused = true
        end
      end
      t.ok(barred, cls .. " is not barred from grouping")
      t.ok(focused, cls .. " does not take its own focus")
    end
  end)

  t.it("names every prompt class a helper actually spawns", function()
    -- The vocabulary lives in conf/base.lua and three rules agree on it. A
    -- class that drifts out of the list breaks all of them silently.
    local declared = {}
    for _, cls in ipairs(require("conf.base").apps.declared_group_prompts) do
      declared[cls] = true
    end
    for _, cls in ipairs({ "Proj-picker", "Proj-confirm", "Log-picker" }) do
      t.ok(declared[cls], cls .. " is spawned by a helper but not declared a prompt")
    end
  end)
end)
