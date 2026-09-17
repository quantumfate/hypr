#!/usr/bin/env bash
# Two test-class windows on a group-block scene form one Hyprland group.
# No eval.
. "$(dirname "$0")/../lib.sh"

e2e_start
go_workspace grouped
spawn_test_window e2e-grp-a
spawn_test_window e2e-grp-b

in_one_group() {
    clients | jq -e '
      map(select(.class == "e2e-grp-a" or .class == "e2e-grp-b")) as $w
      | ($w | length) == 2
        and ($w | all((.grouped | length) == 2))
        and ($w[0].grouped | sort) == ($w[1].grouped | sort)' >/dev/null
}
wait_until 50 in_one_group || e2e_fail "e2e-grp-a and e2e-grp-b are not one group: $(clients | jq -c 'map({class, grouped, workspace: .workspace.name})')"
e2e_log "PASS group"
