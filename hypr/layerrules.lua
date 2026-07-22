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

-- Passive peek cheatsheet: non-interactive contextual panel (no dim backdrop,
-- no keyboard focus — see CheatSheetPeek.qml). The fade is owned by the QML
-- (fast in, slower out, independent timing), so the compositor maps it with no
-- animation of its own — it just frosts the card, like the Dofus HUD.
hl.layer_rule({
  match = { namespace = "quickshell-cheatsheet-peek" },
  animation = "none",
  blur = true,
  ignore_alpha = 0.1,
})

-- Window rename widget: small centered modal, same feel as the cheatsheet.
hl.layer_rule({
  match = { namespace = "quickshell-window-rename" },
  animation = "popin 92%",
  blur = true,
  ignore_alpha = 0.6,
})

-- Team selector: small top-right panel, no dim backdrop. Frost the card,
-- slide in from the right edge.
hl.layer_rule({
  match = { namespace = "quickshell-team-selector" },
  animation = "slidefade 20%",
  blur = true,
  ignore_alpha = 0.1,
})

-- Fallback for any quickshell surface that doesn't set its own namespace: a
-- gentle fade instead of the old blanket "no animations".
hl.layer_rule({ match = { namespace = "^(quickshell)$" }, animation = "fade" })
