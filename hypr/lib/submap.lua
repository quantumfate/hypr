local M = {}

-- Which-key style submap navigation.
--
-- Hyprland submaps are a single global runtime state, so nesting needs a stack
-- on our side to know where "back" and "out" lead. This module owns that stack
-- and is the single way submaps are built in this config (via M.tree), so
-- navigation is consistent everywhere:
--   * entering a group      -> push, so escape can return to the parent
--   * using a leaf action    -> pop the whole tree, back to where we started
--   * escape                 -> pop one level (the previous tree member)
--   * shift+escape           -> hard reset to the root submap

-- The path of submap names currently entered. #stack == depth in the tree.
---@type string[]
local stack = {}
-- Per-submap lifecycle callbacks, keyed by submap name. `enter` fires just
-- after a submap becomes active; `leave` fires when it is popped (via back,
-- a leaf action's exit, or reset). Used to sync external state — e.g. tell the
-- Quickshell UI which team submap is active. Registered from tree specs.
---@type table<string, { enter?: fun(), leave?: fun() }>
local hooks = {}
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

---Fire a submap's lifecycle callback, if registered.
---@param name string
---@param phase "enter"|"leave"
local function fire(name, phase)
	local h = hooks[name]
	if h and h[phase] then
		h[phase]()
	end
end

-- Optional global callback fired whenever *any* submap is entered (including
-- nested ones). Set by config to, e.g., peek the which-key cheatsheet.
---@type fun(name: string)?
M.on_enter = nil

---Enter a submap, remembering where we came from.
---@param name string
function M.enter(name)
	if #stack == 0 then
		base = hl.get_current_submap()
	end
	stack[#stack + 1] = name
	hl.dispatch(hl.dsp.submap(name))
	fire(name, "enter")
	if M.on_enter then
		M.on_enter(name)
	end
end

---Go back one level: to the parent submap, or the base if at the top.
function M.back()
	local leaving = table.remove(stack)
	if leaving then
		fire(leaving, "leave")
	end
	hl.dispatch(hl.dsp.submap(stack[#stack] or base))
end

-- Optional global callback fired whenever the tree is fully left via M.exit
-- (i.e. a non-sticky submap closing after a button press). Set by config to,
-- e.g., dismiss the which-key cheatsheet. Not fired by back/reset/escape.
---@type fun()?
M.on_exit = nil

---Leave the whole tree: clear the stack and return to the base submap. This is
---the which-key "picked a command, close the menu" behaviour.
function M.exit()
	for i = #stack, 1, -1 do
		fire(stack[i], "leave")
	end
	stack = {}
	hl.dispatch(hl.dsp.submap(base))
	if M.on_exit then
		M.on_exit()
	end
end

---Hard reset to the root ("reset") submap regardless of depth.
function M.reset()
	for i = #stack, 1, -1 do
		fire(stack[i], "leave")
	end
	stack = {}
	hl.dispatch(hl.dsp.submap("reset"))
end

-- SubmapEntry / SubmapSpec are defined in hypr/types.lua.

---Full "+MOD+...+key+" trigger string for an entry.
---@param e SubmapEntry
---@return string
local function combo(e)
	local parts = {}
	for _, m in ipairs(e.mods or {}) do
		parts[#parts + 1] = m
	end
	parts[#parts + 1] = e.key
	return keystr(parts)
end

---@param name string
---@param entries SubmapEntry[]
---@param sticky boolean whether leaves stay in the submap by default (modal)
local function define(name, entries, sticky)
	hl.define_submap(name, function()
		for _, e in ipairs(entries) do
			if e.entries then
				local child = e.name or (name .. "-" .. e.key)
				local child_sticky = e.sticky
				if child_sticky == nil then
					child_sticky = sticky
				end
				hooks[child] = { enter = e.on_enter, leave = e.on_leave }
				hl.bind(combo(e), function()
					if e.action then
						run(e.action)
					end
					M.enter(child)
				end, { description = (e.desc or child) .. "…" })
				define(child, e.entries, child_sticky)
			else
				local stay = e.stay
				if stay == nil then
					stay = sticky
				end
				local opts = {}
				for k, v in pairs(e.opts or {}) do
					opts[k] = v
				end
				opts.description = opts.description or e.desc
				opts.repeating = e.repeating
				hl.bind(combo(e), function()
					run(e.action)
					if not stay then
						M.exit()
					end
				end, opts)
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

---Define a submap tree. Entries with `entries` are navigable groups; entries
---with `action` are leaves that run then close the tree (unless `stay`, or the
---submap is `sticky`, in which case leaves stay by default).
---@param spec SubmapSpec
function M.tree(spec)
	hooks[spec.name] = { enter = spec.on_enter, leave = spec.on_leave }
	hl.bind(keystr(spec.mods), function()
		M.enter(spec.name)
	end, { description = (spec.desc or spec.name) .. "…" })
	define(spec.name, spec.entries, spec.sticky or false)
end

return M
