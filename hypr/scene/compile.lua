-- Scene declarations to static window rules (LEO-245, LEO-354).
--
-- Grouping has to be asserted twice — once at config load so a window is born
-- in the right group, once at runtime so it stays there — but it must only be
-- *decided* once. Before this, the compile-time half was hand-written in
-- windowrules.lua and the runtime half was the engine, and the two disagreed:
-- `set always` joins whatever group is focused, so the static rule could put
-- a window in the wrong group and the engine would then spend a pass undoing
-- it. Now the scene is the single source and this file is its compiler.
--
-- Per lifecycle.md D2, a class must group only on its own scene's workspace:
-- two scenes that both declare `Kitty-Main` must not pool a class-wide group
-- across both workspaces. A bare `match = { class = class }` group rule
-- cannot express that — it is global. So grouping is compiled in two rules
-- per class: first a tagging rule, scoped to the scene's workspace, that
-- stamps `scene:<name>` and `block:<name>/<order>` (Hyprland tags, assigned
-- at identify time — before any group rule can apply); then the group rule
-- itself, matched on the block tag rather than the bare class. A window of
-- the same class on a different workspace never receives the tag, so it
-- never matches the group rule either.
--
-- The workspace scope is `match.workspace`: inside `match` it tests the
-- window's workspace, while a top-level `workspace` is the effect that moves
-- a window there. `onworkspace` is not a match key in the Lua API; the
-- compositor rejects it at load.
local M = {}

---One compiled window rule, before it is registered against `hl`. Kept as
---plain data so `plan` stays pure and a spec can assert on it directly.
---@class Scene.CompiledRule
---@field name string
---@field match table<string, string>
---@field tag string? Hyprland tag-assignment effect, e.g. "+scene:code +block:code/1"
---@field group string? Hyprland group effect, e.g. "set always", "barred", "deny"

---Scene and block tag names, shared by the tagging rule and the group rule
---that depends on it.
---@param scene string
---@param order integer?
---@return string scene_tag, string? block_tag
local function tags_for(scene, order)
  local scene_tag = ("scene:%s"):format(scene)
  local block_tag = order and ("block:%s/%d"):format(scene, order) or nil
  return scene_tag, block_tag
end

---Declaration -> the deterministic list of rules it compiles to. Pure: no
---`hl` call, so a spec can assert on the plan directly instead of reaching
---into a stub's recorded rule list.
---@param specs table<string, Scene.Spec>
---@return Scene.CompiledRule[]
function M.plan(specs)
  local names = {}
  for name in pairs(specs) do
    names[#names + 1] = name
  end
  -- Rule order is config order, so sort: a scene table iterated by `pairs`
  -- would emit rules in a different order every reload.
  table.sort(names)

  local rules = {}

  for _, name in ipairs(names) do
    local spec = specs[name]
    local on_workspace = ("name:%s"):format(name)

    for _, block in ipairs(spec.blocks) do
      local scene_tag, block_tag = tags_for(name, block.order)
      for _, class in ipairs(block.classes) do
        -- Identify: stamp the scene/block tags, but only for a window of
        -- this class that is actually on the scene's own workspace.
        -- Named "-1-tag" / "-2-group" so that sorting rule names (required
        -- for deterministic config-load order) also keeps the tagging rule
        -- ahead of the group rule that depends on its tag.
        rules[#rules + 1] = {
          name = ("scene-%s-%d-%s-1-tag"):format(name, block.order, class),
          match = { class = class, workspace = on_workspace },
          tag = ("+%s +%s"):format(scene_tag, block_tag),
        }
        -- Arrange: the group decision matches the block tag, not the bare
        -- class, so it only ever fires for a window already confirmed to be
        -- on this scene's workspace. `set always` rather than `set`: the
        -- default only groups a window the first time, and the point is
        -- that it holds for the fifth project terminal as much as the
        -- first. `barred` on every non-group block keeps `auto_group` from
        -- swallowing the browser into the tab strip beside it.
        rules[#rules + 1] = {
          name = ("scene-%s-%d-%s-2-group"):format(name, block.order, class),
          match = { tag = block_tag },
          group = block.group and "set always" or block.guard,
        }
      end
    end

    -- Classes that legitimately land on the scene's workspace without being
    -- part of any block — a game, a launcher overlay. They are barred rather
    -- than left alone because `auto_group` grabs whatever opens while a group
    -- has focus, and these open into a workspace whose main tile is a group.
    -- Scoped the same way: tag on the scene's workspace, then match the tag.
    for _, class in ipairs(spec.barred) do
      local scene_tag = tags_for(name)
      rules[#rules + 1] = {
        name = ("scene-%s-barred-%s-1-tag"):format(name, class),
        match = { class = class, workspace = on_workspace },
        tag = ("+%s"):format(scene_tag),
      }
      rules[#rules + 1] = {
        name = ("scene-%s-barred-%s-2-group"):format(name, class),
        match = { tag = scene_tag },
        group = "barred",
      }
    end
  end

  return rules
end

---Register the plan against the live `hl` runtime.
---@param specs table<string, Scene.Spec>
function M.emit(specs)
  for _, rule in ipairs(M.plan(specs)) do
    hl.window_rule({
      name = rule.name,
      match = rule.match,
      tag = rule.tag,
      group = rule.group,
    })
  end
end

return M
