---@class NotifyWrapper
local M = {}

local colors = require("hypr.themes.macchiato")

---@enum NotifyLevel
M.level = {
	INFO = "INFO",
	WARNING = "WARNING",
	ERROR = "ERROR",
}

M.colors = {
	[M.level.INFO] = colors.mauve,
	[M.level.WARNING] = colors.peach,
	[M.level.ERROR] = colors.red,
}

---@param text string
---@param duration integer
---@param level NotifyLevel
function M:notify(text, duration, level)
	hl.notification.create({
		text = text,
		duration = duration,
		color = self.colors[level],
	})
end

M.__index = M

return M
