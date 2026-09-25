-- Animations & bezier curves (ported from conf/animations.conf).

hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1.0 } } })
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })
hl.curve("defout", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })
hl.curve("overshot", { type = "bezier", points = { { 0.18, 0.95 }, { 0.22, 1.03 } } })
hl.curve("smoothOut", { type = "bezier", points = { { 0.5, 0 }, { 0.99, 0.99 } } })
hl.curve("smoothIn", { type = "bezier", points = { { 0.5, -0.5 }, { 0.68, 1.5 } } })

hl.config({ animations = { enabled = true } })

hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 3, bezier = "default" })
hl.animation({ leaf = "windows", enabled = true, speed = 4.79, bezier = "easeOutQuint" })
-- Plain map/unmap, no custom style. A deck column scrolling used to be
-- carried by these two (bb15705): the shown member moved onto the workspace
-- and the one it replaced moved off to `special:deck-hold`, which reads to
-- Hyprland as a window appearing/vanishing on this workspace. LEO-402 found
-- that framing was itself the animation bug -- a cross-workspace move fires
-- no leaf this build has, so nothing here ever actually animated the swap
-- (the vertical "slide bottom"/"slide top" above only ever fired for a
-- genuine open/close). The fix keeps every deck member on one workspace and
-- moves the hidden ones off-screen, which is an ordinary reposition
-- (`windowsMove` below), not a map/unmap -- these two leaves have nothing
-- deck-specific left to carry.
hl.animation({ leaf = "windowsIn", enabled = true, speed = 3, bezier = "default" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3, bezier = "default" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade", enabled = true, speed = 3, bezier = "default" })
-- Stepping through a group's tabs (`mod+j/k`) is not two windows appearing
-- and disappearing, it is one tile showing a different member -- and the
-- cross-fade for it reads as a flicker, because the outgoing member fades out
-- over the incoming one in the same box (live complaint, 2026-09-25). The
-- swap is a cut: the tab you asked for is simply the one that is there.
hl.animation({ leaf = "fadeSwitch", enabled = false })
hl.animation({ leaf = "layers", enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "linear", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
-- A workspace change is a cut, not a slide. The workspace animation moved
-- the whole scene in from an edge, and with `windowsMove`'s `slide top` gone
-- it was the rest of the same complaint: the desk jumped on every switch
-- (live, 2026-09-25). Disabling the parent leaf takes `workspacesIn`/
-- `workspacesOut` with it -- neither is overridden here, so both inherit it.
-- Window moves WITHIN a workspace still animate (`windowsMove` below); this
-- is only about the workspace arriving.
hl.animation({ leaf = "workspaces", enabled = false })
-- No `style`: a move animates from where the window WAS to where it is
-- going. `slide top` (07a8540) forced every move to come from the top edge
-- instead, and that fires for far more than the deck -- a workspace change
-- re-tiles its windows, so the whole scene was dragged up and dropped back
-- on every switch (live complaint, 2026-09-25, and the previous comment
-- here named this as the thing to check if a move ever read wrong).
--
-- The deck's scroll (LEO-402) does not need the style and keeps its slide:
-- flipping is an ordinary `window.move` between the visible slot and the
-- off-screen hold, and this leaf animates that reposition either way --
-- docs/deck.md's "the slide is therefore free" is about the leaf, never
-- about its style.
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4, bezier = "default" })
hl.animation({ leaf = "specialWorkspaceIn", enabled = true, speed = 5, bezier = "default", style = "slidefadevert" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 5, bezier = "defout", style = "slidefadevert" })
