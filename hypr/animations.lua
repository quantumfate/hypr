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
hl.animation({ leaf = "layers", enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "linear", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "default" })
-- Vertical slide, load-bearing for the deck now (LEO-402), not merely
-- decorative: every deck member lives on one workspace, and scrolling is
-- exactly a member's box moving from the visible slot to off-screen (and
-- back) -- an ordinary reposition, so `windowsMove` is the only leaf that
-- ever fires for it. `slide top` (07a8540) landed before that mechanism
-- existed and was unverified for ordinary horizontal moves elsewhere on
-- the desk (a scene block re-tiling, say); it stands unchanged here because
-- removing it would silence the deck's scroll entirely, but it is still the
-- one thing worth checking live if some other window's move ever reads
-- wrong -- see docs/deck.md's live-verification note.
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4, bezier = "default", style = "slide top" })
hl.animation({ leaf = "specialWorkspaceIn", enabled = true, speed = 5, bezier = "default", style = "slidefadevert" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 5, bezier = "defout", style = "slidefadevert" })
