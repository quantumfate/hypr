# session/ — Hyprland session glue

Files absorbed out of chezmoi that belong to the Hyprland _session_ (not the
compositor config proper). Deployed by `ansible/roles/hypr`.

| File                          | Deployed to                                  | Notes                                                                                                  |
| ----------------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `uwsm/env-hyprland`           | `~/.config/uwsm/env-hyprland`                | GPU block gated by `hypr_gpu`.                                                                         |
| `systemd/hypridle.service`    | `~/.config/systemd/user/hypridle.service`    | Custom unit, bound to the hyprland session target.                                                     |
| `systemd/awww-daemon.service` | `~/.config/systemd/user/awww-daemon.service` | Custom unit; `PartOf=monitors-changed.target`. Restores the cached last wallpaper per output on login. |
| `systemd/theme-auto.service`  | `~/.config/systemd/user/theme-auto.service`  | Declared by the desk (`scene-managed.json`) but never written until now; runs `,theme.sh apply`.       |
| `systemd/theme-auto.timer`    | `~/.config/systemd/user/theme-auto.timer`    | Hourly sun check -- `daytime()` splits day from night on the hour. `Persistent=true`.                  |
| `greeter/dms-hypr.conf`       | greeter config dir (DMS greeter)             | Login-screen Hyprland fragment.                                                                        |

Not owned here (packaged units, only **enabled** into the session by both
paths): `hyprsunset.service`, `hyprpolkitagent.service` — shipped by their
packages under `/usr/lib/systemd/user/`.
