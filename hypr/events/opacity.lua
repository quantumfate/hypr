local opaque_media_browser = hl.window_rule({
	name = "opaque-media-browser",
	enabled = false,
	match = { tag = "media-browser" },
	opacity = "1.0 override",
})

local opaque_default_browser = hl.window_rule({
	name = "opaque-default-browser",
	enabled = false,
	match = { tag = "default-browser" },
	opacity = "1.0 override",
})

---@param w HL.Window
---@param tag string
---@return boolean
local function is_tagged_browser(w, tag)
	if type(w.tags) == "table" then
		if
			require("hypr.lib.fn").any(function(p)
				return p == tag
				---@diagnostic disable-next-line: param-type-mismatch
			end, w.tags) or w.tags == tag
		then
			return true
		end
	end
	return false
end

---@param w HL.Window
---@param w_rule HL.WindowRule
local function toggle_media_opacity(w, w_rule)
	if w.title:lower():find("crunchyroll") or w.title:lower():find("twitch") or w.title:lower():find("youtube") then
		w_rule:set_enabled(true)
	else
		w_rule:set_enabled(false)
	end
end

hl.on(
	"window.update_rules",
	---@param w HL.Window
	function(w)
		if is_tagged_browser(w, "media-browser*") then
			toggle_media_opacity(w, opaque_media_browser)
		end
		if is_tagged_browser(w, "default-browser*") then
			toggle_media_opacity(w, opaque_default_browser)
		end
	end
)
