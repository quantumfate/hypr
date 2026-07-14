local M = {}

local notify = require("hypr.lib.notify")

---Context handed to every layout action handler.
---@class LayoutContext
---@field ws HL.Workspace The active (special or normal) workspace.
---@field layout string The workspace's tiled_layout.

---registry[action][layout] = handler
---@type table<string, table<string, fun(ctx: LayoutContext)>>
local registry = {}

---fallback[action] = handler, used when the active layout has no specific one.
---@type table<string, fun(ctx: LayoutContext)>
local fallback = {}

---A layout's own submap of layoutmsg bindings, reached via the layout submap.
---@class LayoutSubmap
---@field layout string The layout this submap drives, e.g. "dwindle".
---@field key string Key that opens it from the layout submap, e.g. "d".
---@field entries SubmapEntry[] The layout ops, as submap.tree entries.

---@type LayoutSubmap[]
local submaps = {}

---Register a layout's handlers for named actions. Call from each layout file so
---the layout-specific behaviour lives next to that layout's config.
---@param layout string e.g. "dwindle" | "scrolling" | "master" | "monocle"
---@param actions table<string, fun(ctx: LayoutContext)>
function M.register(layout, actions)
	for name, handler in pairs(actions) do
		registry[name] = registry[name] or {}
		registry[name][layout] = handler
	end
end

---Register handlers used when the active layout registered none of its own.
---@param actions table<string, fun(ctx: LayoutContext)>
function M.register_fallback(actions)
	for name, handler in pairs(actions) do
		fallback[name] = handler
	end
end

---Resolve the active workspace and its layout, then run the action's handler.
---Bound to a key via bind.layout_action; resolution happens at press time.
---@param action string
function M.dispatch(action)
	local ws = hl.get_active_special_workspace() or hl.get_active_workspace()
	if not ws then
		return
	end
	local layout = ws.tiled_layout
	local handler = (registry[action] and registry[action][layout]) or fallback[action]
	if not handler then
		notify:notify(("No '%s' handler for layout '%s'"):format(action, tostring(layout)), 3000, "WARNING")
		return
	end
	handler({ ws = ws, layout = layout })
end

---Register a layout's submap of layoutmsg bindings. Colocated in each layout
---file; wired into the layout submap (SUPER+x) in binds.lua.
---@param spec LayoutSubmap
function M.register_submap(spec)
	submaps[#submaps + 1] = spec
end

---@return LayoutSubmap[]
function M.get_submaps()
	return submaps
end

return M
