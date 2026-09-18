-- Pure decision: which shortcut moves the picker's selection for a given
-- ALT+TAB direction. Kept apart from the executor (alttab.lua's
-- `hl.dispatch(hl.dsp.send_shortcut(...))` call) so the mapping is a plain
-- function a spec can assert on without a compositor.
local M = {}

---@alias AltTab.Direction "up"|"down"

---The fzf picker is started with `--bind tab:down,shift-tab:up`, so moving
---forward is a bare tab and reversing is shift+tab — direction and shift are
---the same bit, just spelled the way `hl.dsp.send_shortcut` wants it.
---@param direction AltTab.Direction
---@return { mods: string, key: string }
function M.shortcut_for(direction)
  return { mods = direction == "up" and "SHIFT" or "", key = "tab" }
end

return M
