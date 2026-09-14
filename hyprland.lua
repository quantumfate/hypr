-- The boot file Hyprland loads. Everything it says is ORDER, not
-- configuration: the desk lives in conf/ (base in conf/base.lua, one file per
-- host in conf/hosts/ — the fallback desk when this machine has none), the
-- compositor wiring in hypr/.
local hypr_dir = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr"
package.path = package.path .. ";" .. hypr_dir .. "/?.lua"

require("conf.host").build()

require("hypr")
