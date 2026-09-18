local cycle = require("hypr.services.alttab.cycle")

---@class AltTab
---@field alttab_dir string runtime directory for pipes
---@field preview_png string runtime directory for pipes
---@field filter_classes string[] search results constrained to a class if a winow with the respective class is focused
local M = {}

M.alttab_dir = os.getenv("XDG_RUNTIME_DIR") .. "/hypr/alttab"
M.preview_png = M.alttab_dir .. "/preview.png"
M.filter_classes = { "Dofus.x64" }

---A window's workspace is special (held windows, shelves, …) when either the
---id Hyprland assigns it is negative or, since that id is nil after a
---rename until the workspace is re-resolved, its name still carries the
---"special:" prefix. Either signal alone is enough; a bare `w.workspace.id
--->= 0` crashes on the nil case instead of reading as "not special".
---@param ws table? `w.workspace`
---@return boolean
local function is_special_workspace(ws)
  if not ws then
    return true
  end
  if ws.id and ws.id < 0 then
    return true
  end
  return type(ws.name) == "string" and ws.name:sub(1, #"special:") == "special:"
end

---Monitors this host withholds from the picker. Config-less specs (and a
---host that has never named any) see an empty set rather than nil.
---@return table<string, true>
local function ignored_monitors()
  local host = (rawget(_G, "config") or {}).host
  local names = (host and host.ignored_monitors) or {}
  local out = {}
  for _, name in ipairs(names) do
    out[name] = true
  end
  return out
end

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
    -- ALT+TAB is bound `submap_universal`, on purpose, so it can open the
    -- picker from anywhere — but that also means every repeat press while
    -- the picker is already open fires this same handler instead of falling
    -- through to fzf's own tab/shift-tab binds. Forward it there instead of
    -- swallowing the press, or the selection can never move (LEO-375).
    local shortcut = cycle.shortcut_for(direction)
    hl.dispatch(hl.dsp.send_shortcut({ mods = shortcut.mods, key = shortcut.key, window = "class:alttab" }))
    return
  end

  if prev_submap == "" then
    prev_submap = "reset"
  end

  os.execute("mkdir -p '" .. M.alttab_dir .. "'")

  local filter = false
  local active_window = hl.get_active_window()
  if active_window then
    for _, class in ipairs(M.filter_classes) do
      if active_window.class == class then
        filter = true
      end
    end
  end
  ---@diagnostic disable-next-line: need-check-nil
  local windows = filter and hl.get_windows({ class = active_window.class }) or hl.get_windows()
  -- Nil history (never focused this session, or a held/special window) sorts
  -- last rather than crashing the `<` comparator.
  table.sort(windows, function(a, b)
    return (a.focus_history_id or math.huge) < (b.focus_history_id or math.huge)
  end)

  local ignored = ignored_monitors()
  local lines = {}
  for _, w in ipairs(windows) do
    local ws = w.workspace
    local monitor = ws and ws.monitor and ws.monitor.name
    if not is_special_workspace(ws) and not (monitor and ignored[monitor]) then
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
  fzf_colors="prompt:green,pointer:green,current-bg:-1,current-fg:green,"\
"gutter:-1,border:bright-black,current-hl:red,hl:red"
  fzf --color "$fzf_colors" \
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

-- The alt-tab picker is a contextual submap: it is entered programmatically
-- when the picker opens, and its forwarding binds only matter while the
-- class:alttab window is focused. Defining it at config load through the same
-- tree grammar as other submaps makes it visible to which-key and to mode
-- admission, instead of a raw hl.define_submap outside the three classes
-- (LEO-324).
local submap = require("hypr.lib.submap")

submap.tree({
  name = "alttab",
  desc = "Alt-tab picker",
  entries = {
    {
      key = "return",
      desc = "Pick selected window",
      stay = true,
      opts = { window = "class:alttab" },
      action = hl.dsp.send_shortcut({ mods = "", key = "return", window = "class:alttab" }),
    },
    {
      key = "return",
      mods = { "SHIFT" },
      desc = "Pick selected window (reverse)",
      stay = true,
      opts = { window = "class:alttab" },
      action = hl.dsp.send_shortcut({ mods = "SHIFT", key = "return", window = "class:alttab" }),
    },
    {
      key = "escape",
      desc = "Cancel",
      stay = true,
      opts = { window = "class:alttab" },
      action = hl.dsp.send_shortcut({ mods = "", key = "escape", window = "class:alttab" }),
    },
    {
      key = "escape",
      mods = { "SHIFT" },
      desc = "Cancel (reverse)",
      stay = true,
      opts = { window = "class:alttab" },
      action = hl.dsp.send_shortcut({ mods = "SHIFT", key = "escape", window = "class:alttab" }),
    },
  },
})

hl.workspace_rule({ workspace = "special:alttab", gaps_out = 0, gaps_in = 0, border_size = 0 })

hl.window_rule({ match = { class = "alttab" }, no_anim = true })
hl.window_rule({ match = { class = "alttab" }, stay_focused = true })
hl.window_rule({ match = { class = "alttab" }, float = true })
hl.window_rule({ match = { class = "alttab" }, size = { "monitor_w * 0.8", "monitor_h * 0.7" } })
hl.window_rule({ match = { class = "alttab" }, workspace = "special:alttab" })
hl.window_rule({ match = { class = "alttab" }, border_size = 2 })
