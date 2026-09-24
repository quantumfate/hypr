#!/usr/bin/env python3
"""Regenerate the tables in docs/binds.md from the live bind registry.

The census has to come from what the compositor actually holds, not from
reading the source: which binds exist is a runtime fact here (trees are
admitted and withheld per mode), and `hyprctl binds` carries no description
for several of them, so which-key's own registry fills those in.

Decisions already written into the "Where it should live" column are carried
over, keyed by submap and key. This rewrites the rows; it never rewrites the
audit, and it never touches the prose above the first table.
"""

import collections
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOC = os.path.join(HERE, "docs", "binds.md")

# Hyprland's modmask bits, in its own order: ALT is 8 and SUPER is 64, not
# the other way round. Getting these two backwards inverts the label on every
# bind the desk actually uses -- `main_mod` is SUPER (conf/base.lua), and it
# reports as 64.
MOD_BITS = {
    1: "SHIFT",
    2: "CAPS",
    4: "CTRL",
    8: "ALT",
    16: "MOD2",
    32: "MOD3",
    64: "SUPER",
    128: "MOD5",
}

# The submap exits are created without a description on purpose: they are
# re-anchored to the root tree rather than owned by the submap they sit in.
KNOWN = {
    "escape": "Leave this submap, back one level",
    "SHIFT+escape": "Leave the whole tree, back to the base submap",
}


def mods(mask):
    return "+".join(name for bit, name in sorted(MOD_BITS.items()) if mask & bit)


def combo(bind):
    key = bind["key"] or (f"code:{bind['keycode']}" if bind.get("keycode") else "?")
    prefix = mods(bind["modmask"])
    return f"{prefix}+{key}" if prefix else key


def canonical(text):
    """A lookup key with the modifiers in a fixed order.

    hyprctl reports them in bit order and which-key in declaration order, so
    `SHIFT+SUPER+TAB` and `SUPER+SHIFT+TAB` are the same bind spelled two
    ways. Sorting the modifiers makes the two sides meet.
    """
    parts = text.split("+")
    return "+".join(sorted(p.upper() for p in parts[:-1]) + [parts[-1]]).lower()


def whichkey_descriptions(store):
    """(submap, key) -> (description, child submap), from the live registry."""
    with open(os.path.join(store, "whichkey.json"), encoding="utf-8") as fh:
        nodes = json.load(fh)
    out = {}
    for node, body in nodes.items():
        # The registry calls the root "reset"; the compositor calls it "".
        submap = "" if node == "reset" else node
        for item in body.get("items", []):
            key = canonical("+".join(item.get("mods", []) + [item["key"]]))
            out[(submap, key)] = (item.get("desc", ""), item.get("child"))
    return out


def existing_decisions(path):
    """(submap, key) -> the decision already written in the third column."""
    if not os.path.exists(path):
        return {}
    decisions, submap = {}, ""
    row = re.compile(r"^\|\s*`([^`]+)`\s*\|(.*)\|(.*)\|\s*$")
    for line in open(path, encoding="utf-8"):
        heading = re.match(r"^## .*?`([^`]+)` submap", line)
        if heading:
            submap = heading.group(1)
        elif line.startswith("## Root"):
            submap = ""
        match = row.match(line)
        if match and match.group(3).strip():
            decisions[(submap, canonical(match.group(1)))] = match.group(3).strip()
    return decisions


def main():
    store = os.environ.get("QF_STORE") or os.path.expanduser(
        "~/.local/state/quantum-store"
    )
    binds = json.loads(subprocess.check_output(["hyprctl", "binds", "-j"]))
    described = whichkey_descriptions(store)
    decisions = existing_decisions(DOC)

    by_submap = collections.defaultdict(list)
    for bind in binds:
        by_submap[bind["submap"]].append(bind)

    def describe(bind):
        if bind.get("description"):
            return bind["description"], None
        key = canonical(combo(bind))
        if combo(bind) in KNOWN:
            return KNOWN[combo(bind)], None
        for candidate in (key, key.split("+")[-1]):
            if (bind["submap"], candidate) in described:
                return described[(bind["submap"], candidate)]
        return "", None

    lines = []
    for submap in [""] + sorted(name for name in by_submap if name):
        rows = by_submap[submap]
        title = "Root — always live" if submap == "" else f"`{submap}` submap"
        lines += [f"\n## {title}\n", f"{len(rows)} binds.\n"]
        lines += ["| Key | Does | Where it should live |", "| --- | --- | --- |"]
        seen = set()
        for bind in sorted(rows, key=lambda b: (mods(b["modmask"]), b["key"] or "")):
            key = combo(bind)
            text, child = describe(bind)
            if child:
                text = f"{text or child} (opens `{child}`)"
            if (key, text) in seen:
                text = f"{text} *(duplicate)*".strip()
            seen.add((key, text))
            decision = decisions.get((submap, canonical(key)), "")
            lines.append(f"| `{key}` | {text or '—'} | {decision} |")

    body = "\n".join(lines) + "\n"
    if os.path.exists(DOC):
        prose = open(DOC, encoding="utf-8").read().split("\n## ", 1)[0].rstrip("\n")
        open(DOC, "w", encoding="utf-8").write(prose + "\n" + body)
    else:
        sys.stdout.write(body)
    kept = sum(1 for k in decisions if k)
    print(f"{len(binds)} binds written to docs/binds.md ({kept} decisions kept)")


if __name__ == "__main__":
    main()
