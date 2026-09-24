# dofus_swap.py — Dofus auto turn-swap

Watches the on-screen "current actor" popup, perceptual-hashes the name pill,
matches against per-character reference hashes, and focuses the matching window
inside the native Dofus group (focus by title + `bring_to_top`, the same
group-tab raise `hypr/services/dofus/team.lua` uses for the F-key walk and press
macro). It is the detector behind the Dofus submap's `s` (`SUPER+d` then `s`,
`hypr/services/dofus/swap.lua`), and can be run directly for debugging.

## Dependencies

Arch / CachyOS via `yay`:

```sh
yay -S python-imagehash python-pillow grim slurp
```

- `python-imagehash` (AUR), `python-pillow` (repo) — perceptual hashing + image I/O.
- `grim` — Wayland screen grab.
- `slurp` — region picker.
- `hyprctl` ships with Hyprland.

No `tesseract` / OCR — a pure phash template match.

## Setup

1. **Calibrate region** (one-time). Start a fight; when the "current actor"
   popup is visible, run:

   ```sh
   dofus_swap.py calibrate
   ```

   Drag a tight box around just the **name pill** (the dark grey rounded
   rectangle with the character name — exclude portrait, exclude the level
   line).

2. **Learn each character.** While each character's popup is showing:

   ```sh
   dofus_swap.py learn Reminiscer
   dofus_swap.py learn Sayer
   # ... one per character on the roster
   ```

   Hashes accumulate in `~/.config/dofus-swap.json`; learning can be done lazily
   across fights. A second grab must match the first, so capture at the popup
   peak — a mid-animation frame is rejected rather than stored.

3. **Verify** (optional):

   ```sh
   dofus_swap.py learned     # list captured hashes
   dofus_swap.py inspect     # while the popup is visible — should show d=0 for that character
   dofus_swap.py list        # see the Hyprland Dofus windows the script will target
   ```

## Run

The roster comes from the shared team store (`$QF_STORE/dofus/team.json`, the
same file the Quickshell UI edits) and is re-read live, so `--characters` is only
an override:

```sh
dofus_swap.py run
dofus_swap.py run --characters Reminiscer Sayer Rejecter   # override the roster
```

Useful flags:

- `--debug` — print every poll tick: brightness, top-3 hash distances. Saves
  the last grab to `/tmp/dofus-swap/last.png`.
- `--dry-run` — detect only, do not focus.

## Tuning

Constants near the top of `dofus_swap.py`:

| Constant         | Default | Effect                                                                                 |
| ---------------- | ------- | -------------------------------------------------------------------------------------- |
| `POLL`           | `0.5`   | Seconds between captures. Lower = snappier, more CPU.                                  |
| `IDLE_POLL`      | `1.5`   | Slower tick when no Dofus window is focused.                                           |
| `HASH_MAX`       | `10`    | Max phash hamming distance (hash_size=16). Tighten if false matches; loosen if missed. |
| `HASH_MARGIN`    | `12`    | Best match must beat the runner-up by this many bits to swap.                          |
| `MIN_BRIGHTNESS` | `5.0`   | Below this average, treat the region as empty (popup gone).                            |
| `STABLE_GAP_S`   | `0.15`  | Re-grab delay while learning; the frame must be steady.                                |
| `STABLE_MAX`     | `4`     | Two learn grabs must be within this hamming distance.                                  |
| `DEBOUNCE_S`     | `0.4`   | Minimum seconds between focus changes.                                                 |
| `RESCAN_S`       | `5.0`   | How often to refresh the window list (catches late-launched clients).                  |

If popup pixels shift slightly across fights (different resolution, scaling
change, etc.), re-`learn` the affected character.

## Limits

- One global popup region. If the popup position is not identical across all
  windows (it should be — same client, same resolution), template match fails.
  If you change resolution, recalibrate and relearn.
- The detector only swaps **to** the active character; it does **not** press
  end-turn. F-key end-turn binds remain manual.
- Stylized Dofus font defeats default tesseract — that is why this is
  phash-based, not OCR-based.
