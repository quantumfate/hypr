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

-- The bar. Its own ground is fully transparent and only the islands are painted
-- (see modules/bar/Island.qml), so ignore_alpha sits just under the island
-- alpha: the glass gets frosted, the empty space between islands stays true
-- wallpaper rather than a blurred smear across the whole top edge.
hl.layer_rule({
  match = { namespace = "quickshell-bar" },
  blur = true,
  ignore_alpha = 0.55,
})

-- Tooltips hang off the bar and should read as the same material.
hl.layer_rule({
  match = { namespace = "quickshell-tip" },
  blur = true,
  ignore_alpha = 0.4,
})

-- Surfaces that had no rule and so fell through to the fade-only fallback,
-- never frosted, while every other card in the shell was. Alphas come from
-- Theme.surfaceAlpha in the quickshell repo — the threshold must stay under the
-- card's alpha or it silently stops being glass.
--
--   notification centre / obsidian / class assigner : modal, 0.97
--   syspanel                                        : peek,  0.85
--   toasts                                          : modal, 0.97
hl.layer_rule({
  match = { namespace = "quickshell-notifications" },
  animation = "slidefade 20%",
  blur = true,
  ignore_alpha = 0.6,
})

hl.layer_rule({
  match = { namespace = "quickshell-obsidian-create" },
  animation = "popin 92%",
  blur = true,
  ignore_alpha = 0.6,
})

hl.layer_rule({
  match = { namespace = "quickshell-class-assigner" },
  animation = "popin 92%",
  blur = true,
  ignore_alpha = 0.6,
})

-- Hover panel off the bar: same material as the tooltips it sits beside.
hl.layer_rule({
  match = { namespace = "quickshell-syspanel" },
  animation = "slidefade 10%",
  blur = true,
  ignore_alpha = 0.4,
})

-- Toasts arrive unbidden, so they slide rather than pop.
hl.layer_rule({
  match = { namespace = "quickshell-toasts" },
  animation = "slidefade 20%",
  blur = true,
  ignore_alpha = 0.6,
})

-- The workspace switcher, the projects dashboard and the calendar. Thresholds
-- sit under Theme.surfaceAlpha's modal (0.97) and peek (0.85).
hl.layer_rule({
  match = { namespace = "quickshell-workspace-switcher" },
  animation = "popin 92%",
  blur = true,
  ignore_alpha = 0.6,
})

hl.layer_rule({
  match = { namespace = "quickshell-projects-dashboard" },
  animation = "slidefade 20%",
  blur = true,
  ignore_alpha = 0.4,
})

hl.layer_rule({
  match = { namespace = "quickshell-calendar" },
  animation = "slidefade 20%",
  blur = true,
  ignore_alpha = 0.4,
})

-- Fallback for any quickshell surface that doesn't set its own namespace: a
-- gentle fade instead of the old blanket "no animations".
hl.layer_rule({ match = { namespace = "^(quickshell)$" }, animation = "fade" })
