# session/ — Hyprland session glue

Files absorbed out of chezmoi that belong to the Hyprland *session* (not the
compositor config proper). Deployed identically by both delivery paths
(`flake.nix` nix modules, `ansible/roles/hypr`).

| File                      | Deployed to                                   | Notes |
| ------------------------- | --------------------------------------------- | ----- |
| `uwsm/env-hyprland`       | `~/.config/uwsm/env-hyprland`                 | GPU block gated by `hypr_gpu`. |
| `systemd/hypridle.service`| `~/.config/systemd/user/hypridle.service`     | Custom unit, bound to the hyprland session target. |
| `systemd/hyprpaper.service`| `~/.config/systemd/user/hyprpaper.service`   | Custom unit; `PartOf=monitors-changed.target`. |
| `greeter/dms-hypr.conf`   | greeter config dir (DMS greeter)              | Login-screen Hyprland fragment. |

Not owned here (packaged units, only **enabled** into the session by both
paths): `hyprsunset.service`, `hyprpolkitagent.service` — shipped by their
packages under `/usr/lib/systemd/user/`.
