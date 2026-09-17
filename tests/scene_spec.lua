-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- The scene engine's wiring (LEO-245): the public surface `hypr/events/scene.lua`
--- exposes, and the static rules `compile.lua` emits from a loaded spec.
---
--- The corrective engine that used to arrange windows here (join/evict/
--- collect via schedule+model+actuator) is retired (LEO-261): geometry now
--- comes only from the registered layout provider, which the compositor
--- calls directly and which is covered by scene_layout_spec/scene_provider_spec.
local t = require("tests.harness")

local GAMING = {
  blocks = {
    { classes = { "Dofus.x64" }, group = true, order = 1, share = 0.67, collect = true },
    { classes = { "zen-gaming-media" }, order = 2, share = 0.33, guard = "deny" },
  },
  barred = { "steam_app_default" },
}

---The scenes live in the declaration's `base.scenes`; the stub hands them
---over in the shape the real store handle answers.
local function define_store(scenes)
  package.loaded["hypr.lib.store"] = {
    define = function()
      return {
        get = function()
          return { base = { scenes = scenes } }
        end,
        put = function(_, doc)
          scenes = doc.base.scenes
        end,
      }
    end,
  }
end

---@return table stub
local function fresh(active)
  local stub = require("tests.hl_stub").new()
  _G.hl = stub
  _G.config = { host = { workspaces = { workspace_specs = {} } } }
  define_store({ gaming = GAMING })
  for _, mod in ipairs({ "hypr.scene.spec", "hypr.events.scene" }) do
    package.loaded[mod] = nil
  end

  local windows = {}
  stub.get_windows = function()
    return windows
  end
  stub.get_active_workspace = function()
    return { id = 4, name = active or "gaming" }
  end
  return stub
end

local function win(stub, over)
  local w = {
    address = over.address,
    class = over.class,
    workspace = { id = over.ws_id or 4, name = over.ws or "gaming" },
    floating = over.floating or false,
    at = { x = over.x or 0, y = 0 },
  }
  stub.get_windows()[#stub.get_windows() + 1] = w
  return w
end

t.describe("public surface", function()
  t.it("names the scene on a workspace it owns", function()
    local stub = fresh()
    local M = require("hypr.events.scene")
    t.eq("gaming", M.active({ id = 4, name = "gaming" }))
    t.eq(nil, M.active({ id = 2, name = "code" }))
    t.eq(nil, M.active(nil))
    t.ok(stub)
  end)

  t.it("returns a block's leftmost tile", function()
    local stub = fresh()
    win(stub, { address = "0x2", class = "Dofus.x64", x = 500 })
    win(stub, { address = "0x1", class = "Dofus.x64", x = 0 })
    local M = require("hypr.events.scene")
    t.eq("0x1", M.tile("gaming", { class = "Dofus.x64" }).address)
    t.eq("0x1", M.tile("gaming", "Dofus.x64").address)
    t.eq(nil, M.tile("gaming", "org.kde.kdenlive"))
  end)
end)

t.describe("compiled rules", function()
  local compile = require("hypr.scene.compile")

  ---Tag stamped for `class` on `scene`'s own workspace, or nil.
  ---@param rules Scene.CompiledRule[]
  ---@param scene string
  ---@param class string
  ---@return string? tag, string? on_workspace
  local function tag_for(rules, scene, class)
    for _, rule in ipairs(rules) do
      local applied_tag = rule.tag and rule.tag:sub(2)
      if rule.match.class == class and applied_tag and applied_tag:find(":" .. scene, 1, true) then
        return applied_tag, rule.match.workspace
      end
    end
    return nil, nil
  end

  -- LEO-369: a rule chained off `match = { tag = ... }` never fires (the
  -- tagging rule's own `workspace` match is not true yet when the window
  -- opens), so compile.lua stops emitting the group/guard effect. It keeps
  -- stamping identity tags — the runtime decision in
  -- hypr/scene/grouping.lua reads a window's block through
  -- `spec_lib.block_for`, not through these tags, but the tags remain
  -- useful identity for other readers (e.g. logging).
  t.it("stamps identity tags only, no group or guard effect", function()
    local rules = compile.plan({
      gaming = {
        name = "gaming",
        blocks = {
          { classes = { "Dofus.x64" }, group = true, order = 1 },
          { classes = { "zen-gaming-media" }, order = 2, guard = "deny" },
        },
        barred = { "steam_app_default" },
      },
    })
    t.eq("scene:gaming", (tag_for(rules, "gaming", "Dofus.x64")))
    for _, rule in ipairs(rules) do
      t.eq(nil, rule.group, rule.name .. " must not emit a group effect")
    end
  end)

  -- Hyprland's `tag` effect takes one tag: "+a +b" stamps a single tag
  -- literally named "a +b".
  t.it("stamps exactly one tag per rule", function()
    local rules = compile.plan({
      dofus = {
        name = "dofus",
        blocks = { { classes = { "Dofus.x64" }, group = true, order = 1 } },
        barred = { "steam_app_default" },
      },
    })
    local stamped = {}
    for _, rule in ipairs(rules) do
      t.ok(rule.tag:match("^%+[^%s+]+$"), "one tag in " .. rule.name .. ": " .. rule.tag)
      stamped[rule.tag] = true
    end
    t.ok(stamped["+scene:dofus"] and stamped["+block:dofus/1"], "block windows get both tags")
    t.ok(stamped["+barred:dofus"], "barred classes get their own tag")
  end)

  -- The cross-scene bug (LEO-354): two scenes declaring the same class used
  -- to compile to one global `match = { class = class }` rule, so a
  -- Kitty-Main opened on either workspace would have shared identity.
  t.it("tags a shared class only on its own scene's workspace", function()
    local specs = {
      code = { name = "code", blocks = { { classes = { "Kitty-Main" }, group = true, order = 1 } }, barred = {} },
      other = { name = "other", blocks = { { classes = { "Kitty-Main" }, group = true, order = 1 } }, barred = {} },
    }
    local rules = compile.plan(specs)

    local code_tag, code_ws = tag_for(rules, "code", "Kitty-Main")
    local other_tag, other_ws = tag_for(rules, "other", "Kitty-Main")
    t.eq("scene:code", code_tag)
    t.eq("scene:other", other_tag)
    t.eq("name:code", code_ws, "the code scene's tagging rule is scoped to the code workspace")
    t.eq("name:other", other_ws, "the other scene's tagging rule is scoped to the other workspace")
  end)

  t.it("plan is pure and deterministically sorted", function()
    local specs = {
      code = { name = "code", blocks = { { classes = { "Kitty-Main" }, group = true, order = 1 } }, barred = {} },
      dofus = {
        name = "dofus",
        blocks = { { classes = { "Dofus.x64" }, group = true, order = 1 } },
        barred = { "steam_app_default" },
      },
    }
    local plan = compile.plan(specs)
    t.eq(plan, compile.plan(specs), "plan is pure: same input, same output")

    local names = {}
    for _, rule in ipairs(plan) do
      names[#names + 1] = rule.name
    end
    local sorted = {}
    for i, name in ipairs(names) do
      sorted[i] = name
    end
    table.sort(sorted)
    t.eq(sorted, names, "rule names are emitted in sorted order")

    local stub = fresh()
    compile.emit(specs)
    t.eq(#plan, #stub.window_rules, "emit registers exactly the planned rules")
  end)
end)
