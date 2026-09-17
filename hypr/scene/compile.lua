-- Scene declarations to static window rules (LEO-245, LEO-354, LEO-369).
--
-- Grouping used to be asserted twice — once at config load so a window is
-- born in the right group, once at runtime so it stays there — but the
-- compile-time half never actually fired. Spiked live (LEO-369): a rule
-- whose `match` includes `workspace = "name:<ws>"` has its tag effect land
-- *after* the window opens, and a second rule chained off that tag (the
-- group rule) never sees a window that already satisfies it — grouping and
-- the `barred`/`deny` guard chained the same way never fired for a single
-- scene block. Group and guard are now decided at runtime, once per
-- `window.open`/`window.move_to_workspace`, by `hypr/scene/grouping.lua` and
-- its executor in `hypr/events/scene.lua`, through the live `HL.Group`
-- object interface (`group.toggle`, `:add`, `:remove`) rather than a static
-- rule.
--
-- Per lifecycle.md D2, a class must still be identified only on its own
-- scene's workspace: two scenes that both declare `Kitty-Main` must not pool
-- identity across both workspaces. A bare `match = { class = class }` rule
-- cannot express that — it is global. So this file keeps compiling the
-- *identity* half: a tagging rule, scoped to the scene's workspace, that
-- stamps `scene:<name>` and `block:<name>/<order>` (Hyprland tags). The
-- runtime grouping decision reads a window's block through
-- `spec_lib.block_for`, the same source these tags describe, so the tags
-- remain useful identity even though nothing chains a group rule off them
-- any more.
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
---@field tag string Hyprland tag-assignment effect, one tag, e.g. "+block:code/1"

---Scene and block tag names, identity only — no group rule depends on them
---any more (see file header).
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
        -- Identify: stamp the scene and block tags, but only for a window
        -- of this class that is actually on the scene's own workspace. One
        -- tag per rule: the `tag` effect takes a single tag, and "+a +b"
        -- would stamp one tag literally named "a +b". Named "-1a"/"-1b" so
        -- sorting rule names stays deterministic.
        rules[#rules + 1] = {
          name = ("scene-%s-%d-%s-1a-scene"):format(name, block.order, class),
          match = { class = class, workspace = on_workspace },
          tag = "+" .. scene_tag,
        }
        rules[#rules + 1] = {
          name = ("scene-%s-%d-%s-1b-block"):format(name, block.order, class),
          match = { class = class, workspace = on_workspace },
          tag = "+" .. block_tag,
        }
      end
    end

    -- Classes that legitimately land on the scene's workspace without being
    -- part of any block — a game, a launcher overlay. Identity only, same as
    -- a block: the runtime grouping decision reads this tag to recognize a
    -- deliberately unblocked class rather than a foreigner `auto_group`
    -- swallowed. The tag is `barred:<name>`, never the scene tag: every
    -- block window carries `scene:<name>` too.
    for _, class in ipairs(spec.barred) do
      local barred_tag = ("barred:%s"):format(name)
      rules[#rules + 1] = {
        name = ("scene-%s-barred-%s-1-tag"):format(name, class),
        match = { class = class, workspace = on_workspace },
        tag = "+" .. barred_tag,
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
    })
  end
end

return M
