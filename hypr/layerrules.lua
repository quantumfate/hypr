-- Layer-shell rules for external surfaces (namespaces set by the app).
-- Quickshell windows set their own namespace via WlrLayershell.namespace so we
-- can style each surface independently (see the quickshell repo modules/*).
-- Field reference: HL.LayerRuleSpec in /usr/share/hypr/stubs/hl.meta.lua.

hl.layer_rule({ match = { namespace = "notifications" }, animation = "slide" })

-- Dofus team HUD: small panel anchored top-right. Slide+fade in from its edge,
-- and blur behind it (the panel is translucent; low ignore_alpha blurs it).
hl.layer_rule({
	match = { namespace = "quickshell-dofus" },
	animation = "slidefade 20%",
	blur = true,
	ignore_alpha = 0.1,
})

-- Cheatsheet: fullscreen overlay (dim backdrop + solid-ish card). Pop in with a
-- subtle zoom (reads better than a flat fade for a centered modal), and frost
-- only the card: ignore_alpha above the backdrop's alpha (~0.5) so the thin dim
-- passes through unblurred while the card gets a blur.
hl.layer_rule({
	match = { namespace = "quickshell-cheatsheet" },
	animation = "popin 92%",
	blur = true,
	ignore_alpha = 0.6,
})

-- Fallback for any quickshell surface that doesn't set its own namespace: a
-- gentle fade instead of the old blanket "no animations".
hl.layer_rule({ match = { namespace = "^(quickshell)$" }, animation = "fade" })
