---@class Config
---@field main_mod string
---@field app_cmds table<string, string>
---@field workspaces Workspaces
---@field host_configs table<string, Hosts>

---@class Workspaces
---@field workspace_specs HL.WorkspaceRuleSpec[]
---@field workspace_keys string[]

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
