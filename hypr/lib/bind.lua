local M = {}

local notify = require("hypr.lib.notify")

---@param mods string[]?
local function parse_mods(mods)
	return mods and "+" .. table.concat(mods, "+") .. "+" or "+"
end

---Binds workspace focus and window move actions
function M.bind_workspaces()
	for i, key in ipairs(config.workspaces.workspace_keys) do
		if config.workspaces.workspace_specs[i] then
			M.focus_workspace(key, tostring(i))
			M.move_focused_to_workspace(key, tostring(i), { "SHIFT" })
		end
	end
end

---@param workspace string
---@return string, string?
local function get_workspace_direction(workspace)
	return workspace:match("%d") and workspace,
		workspace or function()
			if workspace == "e-1" then
				return "previous", workspace
			elseif workspace == "e+1" then
				return "next", workspace
			else
				return workspace, ("name:%s"):format(workspace)
			end
		end
end

---@param key string
---@param workspace string workspace name unless it's a single diget or a "e+" selector
---@param mods string[]?
function M.move_focused_to_workspace(key, workspace, mods)
	local direction, ws_selector = get_workspace_direction(workspace)
	hl.bind(
		config.main_mod .. parse_mods(mods) .. key,
		hl.dsp.window.move({ workspace = ws_selector, follow = true }),
		{
			description = ("Workspace: Move focused to %s"):format(direction),
			submap_universal = true,
		}
	)
end

---@param key string
---@param workspace string workspace name unless it's a single diget or a "e+" selector
---@param mods string[]?
function M.focus_workspace(key, workspace, mods)
	local direction, ws_selector = get_workspace_direction(workspace)
	hl.bind(
		config.main_mod .. parse_mods(mods) .. key,
		hl.dsp.focus({ workspace = ws_selector }),
		{ description = ("Workspace: Focus %s"):format(direction), submap_universal = true }
	)
end
---@param key string
---@param direction string
---@param description string
---@param mods string[]?
function M.move_window_focus(key, direction, description, mods)
	hl.bind(
		config.main_mod .. parse_mods(mods) .. key,
		hl.dsp.focus({ direction = direction }),
		{ description = description }
	)
end

---@param key string
---@param direction string
---@param description string
---@param mods string[]?
function M.swap_windows(key, direction, description, mods)
	hl.bind(
		config.main_mod .. parse_mods(mods) .. key,
		hl.dsp.window.swap({ direction = direction }),
		{ description = description }
	)
end

---@class ExecOpts
---@field description string?
---@field mods string[]?
---@field no_main boolean? skip main_mod prefix
---@field submap_universal boolean?
---@field locked boolean?
---@field repeating boolean?
---@field mouse boolean?

---Generic exec_cmd binding. Defaults: prefix with config.main_mod, no submap_universal/locked/repeating.
---@param key string
---@param cmd string shell command
---@param opts ExecOpts?
function M.exec(key, cmd, opts)
	opts = opts or {}
	local prefix
	if opts.no_main then
		prefix = opts.mods and (table.concat(opts.mods, "+") .. "+") or ""
	else
		prefix = config.main_mod .. parse_mods(opts.mods)
	end
	hl.bind(prefix .. key, hl.dsp.exec_cmd(cmd), {
		description = opts.description,
		submap_universal = opts.submap_universal,
		locked = opts.locked,
		repeating = opts.repeating,
		mouse = opts.mouse,
	})
end

---@param direction "Up"|"Down"
---@param cmd string shell command
function M.brightness(direction, cmd)
	hl.bind(
		"XF86MonBrightness" .. direction,
		hl.dsp.exec_cmd(cmd),
		{ locked = true, repeating = true, description = "Brightness " .. direction:lower() }
	)
end

---@param key string XF86Audio suffix (e.g. "RaiseVolume", "Mute") — "XF86Audio" auto-prepended unless key already starts with "XF86"
---@param cmd string shell command to execute
---@param description string
---@param mods string[]?
---@param repeating boolean?
function M.audio(key, cmd, description, mods, repeating)
	local full_key = key:find("XF86") and key or ("XF86Audio" .. key)
	local prefix = mods and (table.concat(mods, "+") .. "+") or ""
	hl.bind(
		prefix .. full_key,
		hl.dsp.exec_cmd(cmd),
		{ locked = true, repeating = repeating, description = description }
	)
end

---@param key string
---@param app string
---@param description string
---@param mods string[]?
function M.app(key, app, description, mods)
	hl.bind(
		config.main_mod .. parse_mods(mods) .. key,
		hl.dsp.exec_cmd("uwsm app -- " .. app),
		{ description = description, submap_universal = true }
	)
end

---@param key string full binding string (mods + key)
---@param mode "window"|"output"|"region"
---@param description string
function M.screenshot(key, mode, description)
	hl.bind(key, hl.dsp.exec_cmd(",hyprshot.sh --" .. mode), { description = description, submap_universal = true })
end

---@param key string
---@param name string special workspace name
---@param mods string[]?
function M.special_workspace(key, name, mods)
	hl.bind(
		config.main_mod .. parse_mods(mods) .. key,
		hl.dsp.workspace.toggle_special(name),
		{ description = "Toggle Special Workspace " .. name, submap_universal = true }
	)
end

---@param key string
---@param x integer
---@param y integer
---@param mods string[]?
function M.resize_split(key, x, y, mods)
	local description, step = "", 0
	if x == 0 and y > 0 then
		description, step = "horizontally", y
	elseif x > 0 and y == 0 then
		description, step = "vertically", x
	elseif x == 0 and y < 0 then
		description, step = "horizontally", y
	elseif x < 0 and y == 0 then
		description, step = "vertically", x
	else
		notify:notify("Undefined resize behaviour. Not binding resize", 3000, "WARNING")
		return
	end
	hl.bind(
		config.main_mod .. parse_mods(mods) .. key,
		hl.dsp.window.resize({ x = x, y = y, relative = true }),
		{ description = ("Resize " .. description .. " by %s"):format(step), repeating = true }
	)
end

return M
