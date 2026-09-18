#!/usr/bin/env bash
# ,job.sh — start a long-running job as a transient systemd --user unit, so it
# outlives a compositor restart instead of dying with the terminal window that
# started it (LEO-311 chunk A: the one real regression in dropping tmux).
#
# `systemd-run --user`, not `uwsm app --`. `uwsm app --` puts the command in
# the graphical-session's own app.slice, scoped under
# wayland-session@hyprland.desktop.target (AGENTS.md "Respect systemd
# user-manager environment boundaries") — that target is exactly what a
# compositor restart tears down, so a dev server launched through it would die
# at the one moment this exists to prevent. A dev server, build, or watcher
# has no business in the graphical session in the first place: it draws
# nothing and does not need $WAYLAND_DISPLAY. `systemd-run --user` (no
# `--scope`) creates a transient *service* unit instead, parented directly to
# the user manager (user.slice), with its stdout/stderr captured to the
# journal automatically — nothing here to wire up by hand. `--scope` was
# considered and rejected: a scope inherits the caller's own stdio rather than
# redirecting it to the journal, which is right for corralling an interactive
# session's children (systemd-run's usual --scope use) but wrong here, where
# the whole point is a job with no controlling terminal.
#
# The unit name is namespaced `proj-job-<project>-<name>` so ,proj.sh's own
# per-project bookkeeping (LEO-311 chunk C) can find every job a project owns,
# and so two projects can each run a "dev" job without colliding.
#
#   ,job.sh start <project> <name> -- <command...>
#       Start <command> as transient unit proj-job-<project>-<name>. Refuses
#       if that unit is already running (use `restart` to replace it).
#   ,job.sh restart <project> <name> -- <command...>
#       stop, if running, then start.
#   ,job.sh stop <project> <name>
#       Request a graceful stop (SIGTERM, then the unit's TimeoutStopSec).
#   ,job.sh status <project> <name>
#       systemctl --user status for the unit, human output.
#   ,job.sh list [project]
#       Every proj-job-* unit, or one project's.
#   ,job.sh logs <project> <name>
#       journalctl --user -u <unit> -f — or open ,job.sh logview-spec's
#       output in `logview` (see bin/Readme.md) for the windowed version.
#
# Streaming into the logs workspace: the unit IS a systemd unit, so
# `logview unit:<name>` (bin/Readme.md, hypr/services/logging/init.lua)
# already knows how to tail it — no new vocabulary needed there.
#
# What belongs in a unit vs. a terminal window: see bin/Readme.md and
# docs/project-workflow.md.
set -euo pipefail

unit_name() { # $1 = project, $2 = job name
    printf 'proj-job-%s-%s\n' "${1//[^A-Za-z0-9_-]/_}" "${2//[^A-Za-z0-9_-]/_}"
}

die() {
    printf '%s: %s\n' "${0##*/}" "$1" >&2
    exit 1
}

cmd_start() { # $1 = project, $2 = name, rest after -- = command
    local project=$1 name=$2 unit
    shift 2
    [[ ${1-} == -- ]] || die "start: expected -- before the command"
    shift
    (($#)) || die "start: no command given"
    unit=$(unit_name "$project" "$name")
    if systemctl --user is-active --quiet "$unit" 2>/dev/null; then
        die "start: $unit is already running (use restart to replace it)"
    fi
    systemd-run --user \
        --unit="$unit" \
        --description="project job: $project/$name" \
        --collect \
        --working-directory="$PWD" \
        -- "$@"
}

cmd_restart() { # $1 = project, $2 = name, rest after -- = command
    local project=$1 name=$2 unit
    unit=$(unit_name "$project" "$name")
    systemctl --user stop "$unit" 2>/dev/null || true
    cmd_start "$@"
}

cmd_stop() { # $1 = project, $2 = name
    systemctl --user stop "$(unit_name "$1" "$2")"
}

cmd_status() { # $1 = project, $2 = name
    systemctl --user status "$(unit_name "$1" "$2")"
}

cmd_list() { # $1 = project (optional)
    local pattern="proj-job-*"
    [[ -n ${1-} ]] && pattern="proj-job-${1//[^A-Za-z0-9_-]/_}-*"
    systemctl --user list-units --all "$pattern"
}

cmd_logs() { # $1 = project, $2 = name
    journalctl --user -u "$(unit_name "$1" "$2")" -f
}

case "${1-}" in
start) shift && cmd_start "$@" ;;
restart) shift && cmd_restart "$@" ;;
stop) shift && cmd_stop "$@" ;;
status) shift && cmd_status "$@" ;;
list) shift && cmd_list "${1-}" ;;
logs) shift && cmd_logs "$@" ;;
*) die "usage: ,job.sh {start|restart|stop|status|list|logs} <project> <name> [-- command...]" ;;
esac
