---@class Config
---@field main_mod string
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

---@class Hosts
---@field workspaces Workspaces

---@class Match
---@field class string?
---@field initial_class string?
---@field title string?
---@field initial_title string?
---@field tag string?
---@field workspace string?
---@field floating boolean?
---@field fullscreen boolean?
---@field fullscreen_state string?
---@field pinned boolean?
---@field focus boolean?
---@field xwayland boolean?
---@field content string?
---@field group string?
---@field pid integer?
---@field address string?

---@class WindowRuleScope
---@field matches Match[]
---@field tag string with "+" prefix to add tag
---@field props table<string, any>? props applied to bare tag

---@class WorkspaceAssign
---@field match Match
---@field props table<string, any>?

---@class WindowRuleRule
---@field match Match
---@field props table<string, any>

---@class NamedWindowRule
---@field name string
---@field match Match
---@field props table<string, any>

---@class WindowRuleConfig
---@field tag_scopes table<string, WindowRuleScope>
---@field workspace_assigns table<string, WorkspaceAssign[]>
---@field rules WindowRuleRule[]
---@field named table<string, NamedWindowRule>
