local M = {}

-- Which-key style submap navigation.
--
-- Hyprland submaps are a single global runtime state, so nesting needs a stack
-- on our side to know where "back" and "out" lead. This module owns that stack
-- and is shared by every submap in the config (the declarative M.tree below and
-- bind.supmap both drive it), so navigation is consistent everywhere:
--   * entering a group      -> push, so escape can return to the parent
--   * using a leaf action    -> pop the whole tree, back to where we started
--   * escape                 -> pop one level (the previous tree member)
--   * shift+escape           -> hard reset to the root submap

-- The path of submap names currently entered. #stack == depth in the tree.
---@type string[]
local stack = {}
-- The submap that was active before the tree's root was entered; where a leaf
-- action or a full exit returns to.
local base = "reset"

---@param mods string[]
---@return string
local function keystr(mods)
	return "+" .. table.concat(mods, "+") .. "+"
end

---@param action HL.Dispatcher|fun()
local function run(action)
	if type(action) == "function" then
		action()
	else
		hl.dispatch(action)
	end
end

---Enter a submap, remembering where we came from.
---@param name string
function M.enter(name)
	if #stack == 0 then
		base = hl.get_current_submap()
	end
	stack[#stack + 1] = name
	hl.dispatch(hl.dsp.submap(name))
end

---Go back one level: to the parent submap, or the base if at the top.
function M.back()
	table.remove(stack)
	hl.dispatch(hl.dsp.submap(stack[#stack] or base))
end

---Leave the whole tree: clear the stack and return to the base submap. This is
---the which-key "picked a command, close the menu" behaviour.
function M.exit()
	local target = base
	stack = {}
	hl.dispatch(hl.dsp.submap(target))
end

---Hard reset to the root ("reset") submap regardless of depth.
function M.reset()
	stack = {}
	hl.dispatch(hl.dsp.submap("reset"))
end

---A node in a submap tree.
---@class SubmapEntry
---@field key string Key that triggers this entry within its submap.
---@field desc? string Description (shown in the cheatsheet).
---@field entries? SubmapEntry[] Present => a navigable group (nested submap).
---@field name? string Submap name for a group; defaults to "<parent>-<key>".
---@field action? HL.Dispatcher|fun() Present => a leaf; runs on press.
---@field stay? boolean Leaf only: stay in the submap (chainable) instead of exiting.
---@field repeating? boolean Leaf only: allow key repeat.

---@param name string
---@param entries SubmapEntry[]
local function define(name, entries)
	hl.define_submap(name, function()
		for _, e in ipairs(entries) do
			if e.entries then
				local child = e.name or (name .. "-" .. e.key)
				hl.bind(keystr({ e.key }), function()
					M.enter(child)
				end, { description = (e.desc or child) .. "…" })
				define(child, e.entries)
			else
				hl.bind(keystr({ e.key }), function()
					run(e.action)
					if not e.stay then
						M.exit()
					end
				end, { description = e.desc, repeating = e.repeating })
			end
		end
		hl.bind(keystr({ "escape" }), function()
			M.back()
		end)
		hl.bind(keystr({ "SHIFT", "escape" }), function()
			M.reset()
		end)
	end)
end

---A whichkey-style submap tree, opened by a keystroke.
---@class SubmapSpec
---@field mods string[] Keystroke that opens the root submap.
---@field name string Root submap name.
---@field desc? string Description for the opening keybind.
---@field entries SubmapEntry[]

---Define a submap tree. Entries with `entries` are navigable groups; entries
---with `action` are leaves that run then close the tree (unless `stay`).
---@param spec SubmapSpec
function M.tree(spec)
	hl.bind(keystr(spec.mods), function()
		M.enter(spec.name)
	end, { description = (spec.desc or spec.name) .. "…" })
	define(spec.name, spec.entries)
end

return M
