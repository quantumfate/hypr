-- Layer-shell rules for external surfaces (namespaces set by the app).
-- Quickshell windows set their own namespace via WlrLayershell.namespace so we
-- can style each surface independently (see the quickshell repo modules/*).
-- Field reference: HL.LayerRuleSpec in /usr/share/hypr/stubs/hl.meta.lua.

hl.layer_rule({ match = { namespace = "notifications" }, animation = "slide" })

-- 0.55, not 0.6, on every modal below.
--
-- A threshold has to sit between two moving numbers: below the lowest alpha any
-- card can paint, and above the backdrop's. Focus modes made the lower bound
-- real — `media` paints 0.62, and against 0.6 that is a 0.02 margin, close
-- enough that a renderer rounding difference would silently drop the frost.
-- The scrim is 0.5, so 0.55 keeps the dim passing through unblurred while
-- giving the thinnest mood 0.07 of room.
--
-- Cheatsheet: fullscreen reference card, no dim backdrop. Pop in with a subtle
-- zoom (reads better than a flat fade for a centered card), and frost only the
-- card: ignore_alpha sits under the card's alpha so the wallpaper stays visible
-- behind the transparent surround.
hl.layer_rule({
  match = { namespace = "quickshell-cheatsheet" },
  animation = "popin 92%",
  blur = true,
  ignore_alpha = 0.55,
})

-- Which-key overlay (LEO-222 / LEO-327 / LEO-300): recursive submap HUD. Same
-- feel as the cheatsheet — pop in, frost the card — but the QML owns the
-- fade-out timing so dismissal can start before the submap reset lands.
hl.layer_rule({
  match = { namespace = "quickshell-whichkey" },
  animation = "popin 92%",
  blur = true,
  ignore_alpha = 0.55,
})

-- Window rename widget: small centered modal, same feel as the cheatsheet.
hl.layer_rule({
  match = { namespace = "quickshell-window-rename" },
  animation = "popin 92%",
  blur = true,
  ignore_alpha = 0.55,
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
  ignore_alpha = 0.55,
})

hl.layer_rule({
  match = { namespace = "quickshell-obsidian-create" },
  animation = "popin 92%",
  blur = true,
  ignore_alpha = 0.55,
})

hl.layer_rule({
  match = { namespace = "quickshell-class-assigner" },
  animation = "popin 92%",
  blur = true,
  ignore_alpha = 0.55,
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
  ignore_alpha = 0.55,
})

-- The workspace switcher, the projects dashboard and the calendar. Thresholds
-- sit under Theme.surfaceAlpha's modal (0.97) and peek (0.85).
hl.layer_rule({
  match = { namespace = "quickshell-workspace-switcher" },
  animation = "popin 92%",
  blur = true,
  ignore_alpha = 0.55,
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

-- Mood centre (LEO-237): the policy/configuration panel behind the bar's mood
-- pill. Same material as the calendar; its alpha is the active mood's
-- surface_alpha (0.62–0.96), so 0.4 stays clear of the thinnest (media).
hl.layer_rule({
  match = { namespace = "quickshell-mood" },
  animation = "slidefade 20%",
  blur = true,
  ignore_alpha = 0.4,
})

-- Control centre: the one panel over theme, appearance, wallpaper, sound and
-- focus. Modal alpha (0.97) in Theme.surfaceAlpha.
hl.layer_rule({
  match = { namespace = "quickshell-control" },
  animation = "popin 92%",
  blur = true,
  ignore_alpha = 0.55,
})

-- Fallback for any quickshell surface that doesn't set its own namespace: a
-- gentle fade instead of the old blanket "no animations".
hl.layer_rule({ match = { namespace = "^(quickshell)$" }, animation = "fade" })
