#!/usr/bin/env python3
"""Move `^indexof-*` callout blocks written by the Obsidian index-notes plugin
to a canonical position: immediately after the note's H1.

The plugin rewrites an index block in place when it can find the block anchor,
and only appends to the end of the file when it cannot. Relocating the block
once is therefore enough to pin it forever.

Dry-run by default; pass --apply to write.
"""

import argparse
import re
import sys
from pathlib import Path

DEFAULT_VAULT = Path.home() / "Documents/Obsidian/Main"

# Mirrors index-notes' own exclude_folders setting.
EXCLUDED = {
    "Journal",
    "QuickAdd Packages",
    "Templates",
    "__files",
    "__scripts",
    ".obsidian",
}

ANCHOR = re.compile(r"^>\s*\^indexof-[\w-]+\s*$")
CALLOUT_START = re.compile(r"^>\s*\[!")
H1 = re.compile(r"^#\s+\S")
H2 = re.compile(r"^##\s+\S")


def split_frontmatter(lines):
    """Return (body_start_index). Frontmatter is never touched."""
    if not lines or lines[0].rstrip() != "---":
        return 0
    for i in range(1, len(lines)):
        if lines[i].rstrip() == "---":
            return i + 1
    return 0


def find_callout_blocks(lines, start):
    """Yield (block_start, block_end_exclusive) for each callout ending in an anchor.

    A run of `>` lines can hold several callouts with no blank line between them,
    so the run is split at each `> [!...]` header. Without that split an adjacent
    hand-written callout would be dragged along with the index block.
    """
    i = start
    while i < len(lines):
        if not lines[i].startswith(">"):
            i += 1
            continue
        run_start = i
        while i < len(lines) and lines[i].startswith(">"):
            i += 1
        run_end = i

        # Offsets of each callout header within the run; the run may also open
        # with continuation lines belonging to no header.
        heads = [j for j in range(run_start, run_end) if CALLOUT_START.match(lines[j])]
        bounds = (
            [run_start] + heads
            if heads and heads[0] != run_start
            else heads or [run_start]
        )
        bounds = sorted(set(bounds))

        for k, bs in enumerate(bounds):
            be = bounds[k + 1] if k + 1 < len(bounds) else run_end
            if any(ANCHOR.match(line) for line in lines[bs:be]):
                yield bs, be


def normalize(lines):
    """Return rewritten lines, or None if the note is already correct.

    The blocks belong at the foot of the H1 preamble, directly above the first
    H2, so that whatever the note says about itself stays visible above them.
    """
    body_start = split_frontmatter(lines)

    h1 = next((i for i in range(body_start, len(lines)) if H1.match(lines[i])), None)
    if h1 is None:
        return None

    blocks = list(find_callout_blocks(lines, body_start))
    if not blocks:
        return None

    # Without an H2 there is no preamble to sit at the foot of; the plugin's own
    # end-of-note placement is then already the best answer.
    if not any(H2.match(line) for line in lines[h1 + 1 :]):
        return None

    moved = []
    for bs, be in blocks:
        moved.extend(lines[bs:be])
        moved.append("")

    # Drop the originals back-to-front so earlier indices stay valid, absorbing
    # one adjacent blank line so removal leaves no gap behind.
    rest = list(lines)
    for bs, be in reversed(blocks):
        if be < len(rest) and rest[be].strip() == "":
            del rest[bs : be + 1]
        elif bs > 0 and rest[bs - 1].strip() == "":
            del rest[bs - 1 : be]
        else:
            del rest[bs:be]

    h1 = next(i for i in range(split_frontmatter(rest), len(rest)) if H1.match(rest[i]))
    h2 = next(i for i in range(h1 + 1, len(rest)) if H2.match(rest[i]))

    if rest[h2 - 1].strip() != "":
        moved.insert(0, "")
    out = rest[:h2] + moved + rest[h2:]

    return None if out == lines else out


def iter_notes(vault):
    for path in vault.rglob("*.md"):
        rel = path.relative_to(vault)
        if EXCLUDED & set(rel.parts[:-1]):
            continue
        yield path


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--vault", type=Path, default=DEFAULT_VAULT)
    ap.add_argument(
        "--apply", action="store_true", help="write changes (default: dry run)"
    )
    ap.add_argument(
        "paths", nargs="*", type=Path, help="specific notes; default: whole vault"
    )
    args = ap.parse_args()

    targets = args.paths or iter_notes(args.vault)

    changed = 0
    for path in targets:
        text = path.read_text(encoding="utf-8")
        lines = text.split("\n")
        result = normalize(lines)
        if result is None:
            continue
        changed += 1
        if args.apply:
            path.write_text("\n".join(result), encoding="utf-8")
            print(f"moved  {path}")
        else:
            print(f"would move  {path}")

    if not args.apply and changed:
        print(
            f"\n{changed} note(s) would change. Re-run with --apply.", file=sys.stderr
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
