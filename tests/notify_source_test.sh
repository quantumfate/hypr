#!/usr/bin/env bash
# The notification-source convention (LEO-274).
#
# Identity resolution reads hints before it reads app_name, so a sender whose
# identity comes from its own app_name claim is unroutable by design. Every
# notify-send in the desk's bins must carry the x-hyprfocus-source hint —
# usually through ,notify, which makes the convention the easy path. A bare
# notify-send here is a refusal: it can never be routed.
set -euo pipefail

pass=0
fail=0

bin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)"

# Every line in the bin tree that invokes notify-send. `command -v` probes
# are not calls; the helper's exec IS the convention and asserts itself
# below.
while IFS=: read -r file lineno line; do
    case "$file" in
    */,notify) continue ;;                 # the helper: file-level assertion below
    */obsidian_linear_sync.py) continue ;; # argv list: asserted at file level
    */tests/*) continue ;;
    esac
    case "$line" in
    \#*) continue ;; # a comment is not a call
    esac
    case "$line" in
    *"command -v notify-send"*) continue ;;
    esac
    case "$line" in
    *"x-hyprfocus-source"*)
        pass=$((pass + 1))
        printf '  ok   %s:%s sends its source hint\n' "$(basename "$file")" "$lineno"
        ;;
    *)
        fail=$((fail + 1))
        printf '  FAIL %s:%s sends no source hint: %s\n' \
            "$(basename "$file")" "$lineno" "$line"
        ;;
    esac
done < <(grep -rnE --include='*.sh' --include='*.py' '(^|[^ci-])notify-send' \
    "$bin_dir" | sort | grep -v ",notify:" | grep -v "obsidian_linear_sync.py")

# ,notify callers are 'covered by construction' — which is exactly how a
# mis-ordered call (id in the summary slot, a flag before the body) slips
# through: the helper still execs notify-send with the hint. So the shape of
# every ,notify invocation is asserted here, not assumed: <kebab-id>
# <summary> [body] [-u severity], with no notify-send flag the helper does
# not understand (-i, -t) anywhere on the line.
while IFS=: read -r file lineno line; do
    case "$file" in
    */,notify) continue ;; # the helper itself
    */tests/*) continue ;;
    esac
    case "$line" in
    \#*) continue ;; # a comment is not a call
    esac
    args=${line#*,notify }
    read -r id summary _rest <<<"$args"
    case "$id" in
    *-*) ;;
    *)
        fail=$((fail + 1))
        printf '  FAIL %s:%s ,notify source id not kebab-case: %s\n' \
            "$(basename "$file")" "$lineno" "$id"
        continue
        ;;
    esac
    case "$summary" in
    -*)
        fail=$((fail + 1))
        printf '  FAIL %s:%s ,notify flag in the summary slot: %s\n' \
            "$(basename "$file")" "$lineno" "$summary"
        ;;
    *)
        pass=$((pass + 1))
        printf '  ok   %s:%s ,notify is <kebab-id> <summary> [body] [-u …]\n' \
            "$(basename "$file")" "$lineno"
        ;;
    esac
    case "$args" in
    *' -i '* | *' -t '*)
        fail=$((fail + 1))
        printf '  FAIL %s:%s ,notify passes a flag the helper cannot parse: %s\n' \
            "$(basename "$file")" "$lineno" "$line"
        ;;
    esac
done < <(grep -rnE --include='*.sh' ',notify ' "$bin_dir" | sort)

# The helper carries the hint by construction, so a caller using ,notify is
# covered even though its own line says nothing about identity.
if grep -q "x-hyprfocus-source" "$bin_dir/,notify"; then
    pass=$((pass + 1))
    echo "  ok   ,notify is the easy path"
else
    fail=$((fail + 1))
    echo "  FAIL ,notify lost the source hint"
fi
# And the sync's python argv (a list, not a shell line) carries it too.
if grep -q "x-hyprfocus-source" "$bin_dir/obsidian_linear_sync.py"; then
    pass=$((pass + 1))
    echo "  ok   the sync's python sends its source hint"
else
    fail=$((fail + 1))
    echo "  FAIL the sync's python sends no source hint"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
