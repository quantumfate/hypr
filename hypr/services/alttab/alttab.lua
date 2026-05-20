---@class AltTab
---@field alttab_dir string runtime directory for pipes
---@field preview_png string runtime directory for pipes
---@field filter_classes string[] search results constrained to a class if a winow with the respective class is focused
local M = {}

M.alttab_dir = os.getenv("XDG_RUNTIME_DIR") .. "/hypr/alttab"
M.preview_png = M.alttab_dir .. "/preview.png"
M.filter_classes = { "Dofus.x64" }

---@param bind boolean
function M:bind(bind)
	if bind then
		hl.bind("ALT + TAB", function()
			self:alttab("down")
		end, { submap_universal = true })
		hl.bind("ALT + SHIFT + TAB", function()
			self:alttab("up")
		end, { submap_universal = true })
	else
		hl.unbind("ALT + TAB")
		hl.unbind("ALT + SHIFT + TAB")
	end
end

---@param direction string up|down
function M:alttab(direction)
	local prev_submap = hl.get_current_submap()
	if prev_submap == "alttab" then
		return
	end

	if prev_submap == "" then
		prev_submap = "reset"
	end

	os.execute("mkdir -p '" .. M.alttab_dir .. "'")

	local current_class = hl.get_active_window().class
	local filter = false
	for _, class in ipairs(M.filter_classes) do
		if current_class == class then
			filter = true
		end
	end
	local windows = filter and hl.get_windows({ class = current_class }) or hl.get_windows()
	table.sort(windows, function(a, b)
		return a.focus_history_id < b.focus_history_id
	end)

	local lines = {}
	for _, w in ipairs(windows) do
		if w.workspace.id >= 0 then
			lines[#lines + 1] = w.address .. "\t" .. w.title
		end
	end

	local input = M.alttab_dir .. "/input"
	local fin = assert(io.open(input, "w"))
	fin:write(table.concat(lines, "\n"))
	fin:close()

	local sel = M.alttab_dir .. "/address"
	os.remove(sel)

	hl.config({ animations = { enabled = false } })
	hl.dispatch(hl.dsp.submap("alttab"))

	M:bind(false)

	local cmd = ([[footclient -a alttab sh -c ' \
  fzf --color prompt:green,pointer:green,current-bg:-1,current-fg:green,gutter:-1,border:bright-black,current-hl:red,hl:red \
  --cycle --sync --wrap --delimiter="\t" --with-nth=2 --bind tab:down,shift-tab:up,double-click:ignore,start:%s \
  --preview-window=down:80%%,border-none \
  --preview "$XDG_CONFIG_HOME/hypr/hypr/services/alttab/preview.sh {}" \
  --layout=reverse < "%s" > "%s"'

hyprctl eval 'hl.config({ animations = { enabled = true } })'
hyprctl dispatch 'hl.dsp.submap("%s")'
addr=$(cut -f1 "%s")
if [ -n "$addr" ]; then
  hyprctl dispatch 'hl.dsp.focus({ window = "address:'"$addr"'" })'
  hyprctl dispatch 'hl.dsp.window.bring_to_top()'
fi
]]):format(direction, input, sel, prev_submap, sel)

	hl.exec_cmd(cmd)

	M:bind(true)
end

M.__index = M

M:bind(true)

hl.define_submap("alttab", function()
	hl.bind("Return", hl.dsp.send_shortcut({ mods = "", key = "return", window = "class:alttab" }))
	hl.bind("SHIFT + Return", hl.dsp.send_shortcut({ mods = "SHIFT", key = "return", window = "class:alttab" }))
	hl.bind("escape", hl.dsp.send_shortcut({ mods = "", key = "escape", window = "class:alttab" }))
	hl.bind("SHIFT + escape", hl.dsp.send_shortcut({ mods = "SHIFT", key = "escape", window = "class:alttab" }))
end)

hl.workspace_rule({ workspace = "special:alttab", gaps_out = 0, gaps_in = 0, border_size = 0 })

hl.window_rule({ match = { class = "alttab" }, no_anim = true })
hl.window_rule({ match = { class = "alttab" }, stay_focused = true })
hl.window_rule({ match = { class = "alttab" }, float = true })
hl.window_rule({ match = { class = "alttab" }, size = { "monitor_w * 0.8", "monitor_h * 0.7" } })
hl.window_rule({ match = { class = "alttab" }, workspace = "special:alttab" })
hl.window_rule({ match = { class = "alttab" }, border_size = 2 })
