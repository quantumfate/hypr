---@class Dofus.Teams
---@field pioneer string[] turn order (F23 iteration)

---@class Dofus.Common
---@field default_team string
---@field selected string currently selected team key
---@field characters Dofus.Teams
---@field title_prefix string
local M = {}

M.default_team = "pioneer"
M.selected = M.default_team
M.title_prefix = "Dofus "

M.characters = {
	pioneer = {
		"Rejecter",
		"Reminiscer",
		"Sayer",
		"Draintouch",
		"Traumafactory",
		"Memoryfracture",
		"Dissipate",
		"Miserymaker",
	},
}

---Select the active team (no-op if key unknown).
---@param name string team key in M.characters
function M.select(name)
	if M.characters[name] then
		M.selected = name
	end
end

---Currently selected team's character list (turn order = list order).
---@return string[]
function M.team()
	return M.characters[M.selected]
end

return M
