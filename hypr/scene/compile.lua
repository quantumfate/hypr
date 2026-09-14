-- Scene declarations to static window rules (LEO-245).
--
-- Grouping has to be asserted twice — once at config load so a window is born
-- in the right group, once at runtime so it stays there — but it must only be
-- *decided* once. Before this, the compile-time half was hand-written in
-- windowrules.lua and the runtime half was the engine, and the two disagreed:
-- `set always` joins whatever group is focused, so the static rule could put
-- a window in the wrong group and the engine would then spend a pass undoing
-- it. Now the scene is the single source and this file is its compiler.
local M = {}

---Emit the group half of every scene's rules. Rule *properties* (workspace
---pinning, opacity, content type) stay in windowrules.lua next to the rest of
---each app's behavior; only the group decision moves here.
---@param specs table<string, Scene.Spec>
function M.emit(specs)
  local names = {}
  for name in pairs(specs) do
    names[#names + 1] = name
  end
  -- Rule order is config order, so sort: a scene table iterated by `pairs`
  -- would emit rules in a different order every reload.
  table.sort(names)

  for _, name in ipairs(names) do
    local spec = specs[name]
    for _, block in ipairs(spec.blocks) do
      for _, class in ipairs(block.classes) do
        hl.window_rule({
          name = ("scene-%s-%d-%s"):format(name, block.order, class),
          match = { class = class },
          -- `set always` rather than `set`: the default only groups a window
          -- the first time, and the point is that it holds for the fifth
          -- project terminal as much as the first. `barred` on every
          -- non-group block keeps `auto_group` from swallowing the browser
          -- into the tab strip beside it.
          group = block.group and "set always" or block.guard,
        })
      end
    end
    -- Classes that legitimately land on the scene's workspace without being
    -- part of any block — a game, a launcher overlay. They are barred rather
    -- than left alone because `auto_group` grabs whatever opens while a group
    -- has focus, and these open into a workspace whose main tile is a group.
    for _, class in ipairs(spec.barred) do
      hl.window_rule({
        name = ("scene-%s-barred-%s"):format(name, class),
        match = { class = class },
        group = "barred",
      })
    end
  end
end

return M
