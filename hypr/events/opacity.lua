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

hl.on(
	"window.update_rules",
	---comment
	---@param w HL.Window
	function(w)
		if w.title:lower():find("crunchyroll") or w.title:lower():find("twitch") or w.title:lower():find("youtube") then
			opaque_media_browser:set_enabled(true)
			opaque_default_browser:set_enabled(true)
		else
			opaque_media_browser:set_enabled(false)
			opaque_default_browser:set_enabled(false)
		end
	end
)
