---@class Config
---@field main_mod string
---@field workspaces Workspaces
---@field app_cmds Commands
---@field host_configs table<string, Hosts>

---@class Workspaces
---@field workspace_specs HL.WorkspaceRuleSpec[]
---@field workspace_keys string[]

---@class Commands
---@field media_browser string
---@field main_browser string
---@field terminal string
---@field terminal_float string
---@field tmux string
---@field password_manager string
---@field mail string
---@field calculator string
---@field app_launcher string

---@class Layouts
---@field dwindle integer[]
---@field master integer[]
---@field scrolling integer[]
---@field monocle integer[]

---@class Monitors
---@field workspaces integer[]
---@field layouts Layouts

---@alias Monitor string

---@class Hosts
---@field monitors table<Monitor, Monitors>
