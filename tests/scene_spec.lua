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

---The scenes document lives in the state store now; the stub hands it over
---the same shape the real store handle answers.
local function define_store(scenes)
  package.loaded["hypr.lib.store"] = {
    define = function()
      return {
        get = function()
          return { version = require("hypr.scene.defaults").version, scenes = scenes }
        end,
        put = function(_, doc)
          scenes = doc.scenes
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

  ---Group rules match a block/scene tag, not a bare class, so a spec
  ---resolves group/guard by walking tag -> group through the tagging rule
  ---that feeds it, the same way the runtime would.
  ---@param rules Scene.CompiledRule[]
  ---@param scene string
  ---@param class string
  ---@return string? group, string? on_workspace
  local function group_for(rules, scene, class)
    for _, tag_rule in ipairs(rules) do
      if tag_rule.match.class == class and tag_rule.tag and tag_rule.tag:find("scene:" .. scene, 1, true) then
        -- A block class stamps both tags; a barred class stamps only the
        -- scene tag. The group rule depends on whichever is more specific.
        local applied_tag = tag_rule.tag:match("%+(block:[^%s]+)") or tag_rule.tag:match("%+(scene:[^%s]+)")
        for _, group_rule in ipairs(rules) do
          if group_rule.match.tag == applied_tag then
            return group_rule.group, tag_rule.match.workspace
          end
        end
      end
    end
    return nil, nil
  end

  t.it("declares grouping once, from the scene", function()
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
    t.eq("set always", (group_for(rules, "gaming", "Dofus.x64")))
    t.eq("deny", (group_for(rules, "gaming", "zen-gaming-media")), "the block's own guard, not the default bar")
    t.eq("barred", (group_for(rules, "gaming", "steam_app_default")))
  end)

  -- The cross-scene bug (LEO-354): two scenes declaring the same class used
  -- to compile to one global `match = { class = class }` group rule, so a
  -- Kitty-Main opened on either workspace joined the same class-wide group.
  t.it("groups a shared class only on its own scene's workspace", function()
    local specs = {
      code = { name = "code", blocks = { { classes = { "Kitty-Main" }, group = true, order = 1 } }, barred = {} },
      other = { name = "other", blocks = { { classes = { "Kitty-Main" }, group = true, order = 1 } }, barred = {} },
    }
    local rules = compile.plan(specs)

    local code_group, code_ws = group_for(rules, "code", "Kitty-Main")
    local other_group, other_ws = group_for(rules, "other", "Kitty-Main")
    t.eq("set always", code_group)
    t.eq("set always", other_group)
    t.eq("name:code", code_ws, "the code scene's tagging rule is scoped to the code workspace")
    t.eq("name:other", other_ws, "the other scene's tagging rule is scoped to the other workspace")

    -- Distinct block tags mean distinct group rules: a window tagged
    -- `block:code/1` (because it opened on the code workspace) never
    -- satisfies `match = { tag = "block:other/1" }`, and a Kitty-Main opened
    -- on a third, undeclared workspace matches neither tagging rule at all,
    -- so it is never tagged and never reaches a group rule — "gets none".
    local group_rule_tags = {}
    for _, rule in ipairs(rules) do
      if rule.group then
        t.ok(rule.match.class == nil, "group rule " .. rule.name .. " must match a tag, not a class")
        group_rule_tags[rule.match.tag] = true
      end
    end
    t.ok(group_rule_tags["block:code/1"], "code scene has its own group rule")
    t.ok(group_rule_tags["block:other/1"], "other scene has its own, distinct group rule")
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
