#!/usr/bin/env python3
"""Bootstrap the Zettelkasten tag/index structure around the Obsidian CLI.

Bridges three things: the flat vault (`$OBSIDIAN_VAULT/Zettelkasten`), the
Obsidian CLI (Templater `templater:create-from-template` + `property:set`), and
the tag-tree store the desktop reads reactively.

The vault is the source of truth. The store
(`$XDG_STATE_HOME/obsidian/tags.json` + encrypted `tags.json.gpg`) is a
projection `sync` rebuilds and `create` refreshes, so Quickshell's `Store.qml`
can render the structure without scanning notes itself.

Tag model (see the quickshell repo's docs/obsidian-vault-manifest.md):
  <topic>/idx       one note; index-notes plugin lists every note tagged <topic>
  <topic>/meta_idx  one note; pretty render of all indices under <topic>
  <topic>           any number of notes; the leaves an /idx note lists
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_VAULT = Path.home() / "Documents" / "Obsidian" / "Main"
DEFAULT_ROOT = "Zettelkasten"
DEFAULT_RECIPIENT = (
    "45EE29D4AA966DFD"  # Leon Connor Holm's GPG key (gpg --list-secret-keys)
)
STORE_NAME = "obsidian"
SCAN_GLOB = "*.md"

TEMPLATES: dict[str, str] = {
    "fleeting": "Templates/fleeting note.md",
    "atomic": "Templates/atomic note.md",
    "moc": "Templates/moc note.md",
    "journal": "Templates/journal note.md",
    "blog": "Templates/blog post.md",
}

IDX_SUFFIX = "/idx"
META_SUFFIX = "/meta_idx"
PROPERTY_RETRY_S = 10.0  # obsidian property:set needs the app to index new files
PROPERTY_RETRY_STEP = 0.5


# --------------------------------------------------------------------------
# Configuration (all overridable via env, none secret)


class Config:
    def __init__(self) -> None:
        self.vault: Path = Path(
            os.environ.get("OBSIDIAN_VAULT", str(DEFAULT_VAULT))
        ).resolve()
        self.root: str = os.environ.get("OBSIDIAN_ROOT", DEFAULT_ROOT)
        self.cli: str = os.environ.get("OBSIDIAN_CLI", "obsidian")
        self.recipient: str = os.environ.get(
            "OBSIDIAN_GPG_RECIPIENT", DEFAULT_RECIPIENT
        )
        self.store_dir: Path = store_root() / STORE_NAME
        self.plain_store: Path = self.store_dir / "tags.json"
        self.enc_store: Path = self.store_dir / "tags.json.gpg"
        # The one step back, for a store the desk has not migrated yet.
        self.legacy_store: Path = (
            Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local" / "state")))
            / STORE_NAME
            / "tags.json"
        )

    @property
    def vault_root(self) -> Path:
        return self.vault / self.root


# --------------------------------------------------------------------------
# Frontmatter codec

FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---", re.DOTALL)
TAG_VALUE_RE = re.compile(r"'([^']+)'|\"([^\"]+)\"|([\w/\-.]+)")


def parse_frontmatter(text: str) -> dict:
    """Return the frontmatter block as a dict (tags always a list)."""
    m = FRONTMATTER_RE.match(text)
    if not m:
        return {"tags": []}
    lines = m.group(1).split("\n")
    out: dict = {}
    i = 0
    while i < len(lines):
        head = re.match(r"^(\w+):\s*(.*)$", lines[i])
        if not head:
            i += 1
            continue
        key, value = head.group(1), head.group(2).strip()
        if key == "tags":
            tags = [g[0] or g[1] or g[2] for g in TAG_VALUE_RE.findall(value)]
            j = i + 1
            while j < len(lines):
                item = re.match(r"^\s+-\s+(.+)$", lines[j])
                if not item:
                    break
                tags.append(item.group(1).strip())
                j += 1
            out[key] = [t for t in tags if t]
            i = j
        else:
            out[key] = value
            i += 1
    return out


def read_frontmatter(path: Path) -> dict:
    """Parse a note file's frontmatter (empty on missing file)."""
    if not path.exists():
        return {"tags": []}
    return parse_frontmatter(path.read_text(encoding="utf-8"))


# --------------------------------------------------------------------------
# Obsidian CLI


class ObsidianCli:
    """Thin wrapper over the running app's CLI, always bound to the vault."""

    def __init__(self, cfg: Config) -> None:
        self.cfg = cfg

    def _run(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [self.cfg.cli, *args],
            cwd=self.cfg.vault,
            capture_output=True,
            text=True,
        )

    def app_running(self) -> bool:
        # The app runs as `electron<N> /usr/lib/obsidian/app.asar`, so there is no
        # process named "obsidian" to match. The bracket keeps pgrep off this probe.
        probe = subprocess.run(
            ["pgrep", "-f", "[o]bsidian/app.asar"], capture_output=True, text=True
        )
        return probe.returncode == 0

    def create_from_template(
        self, template: str, rel_path: str, open_file: bool
    ) -> None:
        """Create a note via Templater (fills note_id/note_type/date from the template)."""
        proc = self._run(
            "templater:create-from-template",
            f"template={template}",
            f"file={rel_path}",
            f"open={'true' if open_file else 'false'}",
        )
        if proc.returncode != 0:
            raise RuntimeError(
                f"templater:create-from-template failed: {proc.stderr.strip() or proc.stdout.strip()}"
            )
        target = self.cfg.vault / f"{rel_path}.md"
        for _ in range(int(PROPERTY_RETRY_S / PROPERTY_RETRY_STEP)):
            if target.exists():
                return
            time.sleep(PROPERTY_RETRY_STEP)
        raise RuntimeError(f"note not created after retries: {target}")

    def set_tags(self, rel_path: str, tags: list[str]) -> None:
        """Replace a note's tags; waits for the app to index freshly created files."""
        if not tags:
            return
        path_arg = f"{rel_path}.md"
        value = ",".join(tags)
        deadline = time.monotonic() + PROPERTY_RETRY_S
        while True:
            proc = self._run(
                "property:set",
                f"path={path_arg}",
                "name=tags",
                f"value={value}",
                "type=list",
            )
            if proc.returncode == 0 and "Set tags" in proc.stdout:
                return
            if time.monotonic() >= deadline:
                raise RuntimeError(
                    f"property:set tags on {rel_path} failed: {proc.stderr.strip() or proc.stdout.strip()}"
                )
            time.sleep(PROPERTY_RETRY_STEP)


# --------------------------------------------------------------------------
# Tag-tree inference


def humanize(slug: str) -> str:
    """Turn a tag slug into a display title, keeping acronyms (GPG-Keys -> GPG Keys)."""
    return " ".join(
        part if (part and not any(c.islower() for c in part)) else part.capitalize()
        for part in slug.replace("_", "-").split("-")
        if part
    )


def split_topic(tag: str) -> tuple[str, str] | None:
    """Split a tag into (topic, suffix-kind); None for non-index tags."""
    if tag.endswith(META_SUFFIX):
        return tag[: -len(META_SUFFIX)], "meta_idx"
    if tag.endswith(IDX_SUFFIX):
        return tag[: -len(IDX_SUFFIX)], "idx"
    return None


def slug_last(path: str) -> str:
    return path.rpartition("/")[2]


class NoteAction:
    """One bootstrap step: create a new note, or add an index tag to an existing one."""

    def __init__(
        self,
        kind: str,
        title: str,
        tags: list[str],
        note_type: str = "moc",
        open_file: bool = False,
    ) -> None:
        self.kind = kind  # "create" | "add_tags"
        self.title = title
        self.tags = tags
        self.note_type = note_type
        self.open_file = open_file

    def describe(self) -> str:
        if self.kind == "create":
            return f"create {self.note_type} note '{self.title}' tags=[{', '.join(self.tags)}]"
        return f"add tags [{', '.join(self.tags)}] to existing '{self.title}'"


def _ensure_index(
    cfg: Config, topics: dict, topic: str, suffix: str
) -> NoteAction | None:
    """One action (or None) so the topic's <suffix> index note exists."""
    field = "meta_idx_note" if suffix == "meta_idx" else "idx_note"
    other_field = "idx_note" if suffix == "meta_idx" else "meta_idx_note"
    if topics.get(topic, {}).get(field):
        return None
    other = topics.get(topic, {}).get(other_field)
    if other:
        return NoteAction("add_tags", other, [f"{topic}/{suffix}"])
    title = humanize(slug_last(topic))
    path = cfg.vault_root / f"{title}.md"
    if path.exists():
        fm = read_frontmatter(path)
        if not fm.get("tags") and not fm.get("note_type"):
            return NoteAction("add_tags", title, [f"{topic}/{suffix}"])
    unique = title
    while (cfg.vault_root / f"{unique}.md").exists():
        unique = f"{unique} Index"
    return NoteAction("create", unique, [f"{topic}/{suffix}"])


def plan_topic(
    cfg: Config, topics: dict, tag_path: str, chain: bool
) -> list[NoteAction]:
    """Infer the index notes missing for a topic, deepest ancestor first."""
    path = tag_path.strip("/")
    for suffix in (META_SUFFIX, IDX_SUFFIX):
        if path.endswith(suffix):
            path = path[: -len(suffix)]
    segments = path.split("/")
    if not all(re.fullmatch(r"[\w.\-]+", s) for s in segments):
        raise ValueError(f"invalid tag path: {tag_path!r}")

    actions: list[NoteAction] = []
    if chain:
        for depth in range(len(segments) - 1, 0, -1):
            action = _ensure_index(cfg, topics, "/".join(segments[:depth]), "meta_idx")
            if action:
                actions.append(action)
    action = _ensure_index(cfg, topics, path, "idx")
    if action:
        actions.append(action)
    return actions


# --------------------------------------------------------------------------
# Store


def _frontmatter_of(cfg: Config, path: Path) -> dict:
    return read_frontmatter(path)


def scan_vault(cfg: Config) -> dict:
    """Read every note's frontmatter and derive the tag-tree store document."""
    notes: dict = {}
    tag_index: dict[str, dict] = {}
    topics: dict[str, dict] = {}

    for path in sorted(cfg.vault_root.glob(SCAN_GLOB)):
        if not path.is_file():
            continue
        fm = _frontmatter_of(cfg, path)
        title = path.stem
        tags = fm.get("tags", [])
        notes[title] = {
            "note_id": fm.get("note_id", ""),
            "note_type": fm.get("note_type", ""),
            "file": str(path.relative_to(cfg.vault)),
            "tags": tags,
        }
        for tag in tags:
            entry = tag_index.setdefault(
                tag, {"kind": "leaf", "topic": tag, "count": 0, "notes": []}
            )
            kind = split_topic(tag)
            if kind:
                entry["kind"] = kind[1]
                entry["topic"] = kind[0]
            entry["count"] += 1
            entry["notes"].append(title)
            topics.setdefault(
                entry["topic"],
                {
                    "title": None,
                    "idx_note": None,
                    "meta_idx_note": None,
                    "leaf_count": 0,
                },
            )

    for tag, entry in tag_index.items():
        topic = entry["topic"]
        info = topics[topic]
        if entry["kind"] == "idx":
            info["idx_note"] = entry["notes"][0]
        elif entry["kind"] == "meta_idx":
            info["meta_idx_note"] = entry["notes"][0]
        elif topic == tag:
            info["leaf_count"] = entry["count"]

    for path, info in topics.items():
        info["title"] = (
            info["meta_idx_note"] or info["idx_note"] or humanize(slug_last(path))
        )
        info["parent"] = path.rpartition("/")[0]
        info["depth"] = len(path.split("/"))

    tree = _build_tree(topics)
    return {
        "version": 1,
        "generated": datetime.now(timezone.utc).isoformat(),
        "vault": cfg.vault.name,
        "vault_path": str(cfg.vault),
        "root": cfg.root,
        "recipient": cfg.recipient,
        "note_count": len(notes),
        "topic_count": len(topics),
        "templates": TEMPLATES,
        "notes": notes,
        "tags": tag_index,
        "topics": topics,
        "tree": tree,
    }


def _build_tree(topics: dict) -> dict:
    """Nest topics into a tree by '/' prefix (roots are the empty-parent topics)."""

    def child(path: str) -> str:
        return path.split("/")[-1]

    def node(path: str, info: dict) -> dict:
        n = {
            "slug": child(path),
            "title": info["title"] or child(path),
            "idx_note": info["idx_note"],
            "meta_idx_note": info["meta_idx_note"],
            "leaf_count": info["leaf_count"],
        }
        children = {}
        for other_path, other in sorted(topics.items()):
            if (
                other_path.startswith(path + "/")
                and "/" not in other_path[len(path) + 1 :]
            ):
                children[child(other_path)] = node(other_path, other)
        if children:
            n["children"] = children
        return n

    roots = {}
    for path, info in topics.items():
        if "/" not in path:
            roots[child(path)] = node(path, info)
    return roots


def _encrypt(cfg: Config) -> None:
    """GPG-encrypt the plaintext store (batch, no prompt); no-op without a recipient."""
    if not cfg.recipient:
        return
    proc = subprocess.run(
        [
            "gpg",
            "--batch",
            "--yes",
            "--output",
            str(cfg.enc_store),
            "--recipient",
            cfg.recipient,
            "--encrypt",
            str(cfg.plain_store),
        ],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"gpg encrypt failed: {proc.stderr.strip()}")


def _decrypt(cfg: Config) -> dict:
    proc = subprocess.run(
        ["gpg", "--batch", "--quiet", "--decrypt", str(cfg.enc_store)],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"gpg decrypt failed: {proc.stderr.strip()}")
    return json.loads(proc.stdout)


# The shared quantum-store directory: QF_STORE names it, otherwise one dir
# deeper than the pre-store-generation home. A legacy path is a migration
# read only; writes always go forward.
def store_root() -> Path:
    if os.environ.get("QF_STORE"):
        return Path(os.environ["QF_STORE"])
    state = os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local" / "state"))
    return Path(state) / "quantum-store"


def load_store(cfg: Config) -> dict:
    """Load the store, preferring the plaintext mirror then the encrypted copy."""
    if cfg.plain_store.exists():
        return json.loads(cfg.plain_store.read_text(encoding="utf-8"))
    if cfg.enc_store.exists():
        return _decrypt(cfg)
    legacy = cfg.legacy_store
    if legacy.exists():
        return json.loads(legacy.read_text(encoding="utf-8"))
    return scan_vault(cfg)


def save_store(cfg: Config, data: dict, encrypt: bool) -> None:
    cfg.store_dir.mkdir(parents=True, exist_ok=True)
    cfg.plain_store.write_text(
        json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    if encrypt and cfg.recipient:
        _encrypt(cfg)


# --------------------------------------------------------------------------
# Commands


def cmd_sync(cfg: Config, encrypt: bool) -> int:
    data = scan_vault(cfg)
    save_store(cfg, data, encrypt)
    print(
        f"synced {data['note_count']} notes, {data['topic_count']} topics -> {cfg.plain_store}"
    )
    if encrypt and cfg.recipient:
        print(f"encrypted -> {cfg.enc_store} (gpg recipient {cfg.recipient})")
    return 0


def cmd_dump(cfg: Config, raw: bool) -> int:
    data = load_store(cfg)
    if raw:
        print(json.dumps(data, indent=2, ensure_ascii=False))
        return 0

    def render(node: dict, indent: str) -> None:
        suffix = " [meta]" if node.get("meta_idx_note") else ""
        suffix += " [idx]" if node.get("idx_note") else ""
        leaves = f" ({node['leaf_count']} leaf)" if node.get("leaf_count") else ""
        print(f"{indent}{node['title']}{suffix}{leaves}")
        for child in node.get("children", {}).values():
            render(child, indent + "  ")

    for root in data["tree"].values():
        render(root, "")
    return 0


def cmd_status(cfg: Config) -> int:
    store_ok = cfg.plain_store.exists() or cfg.enc_store.exists()
    print(f"vault        {cfg.vault}")
    print(f"root         {cfg.vault_root}")
    print(f"store        {cfg.plain_store} (encrypted: {cfg.enc_store})")
    print(f"recipient    {cfg.recipient or '(none)'}")
    print(f"store built  {store_ok}")
    if store_ok:
        data = load_store(cfg)
        print(f"notes/topics {data['note_count']}/{data['topic_count']}")
    return 0


def _execute(
    cfg: Config, cli: ObsidianCli, actions: list[NoteAction], dry_run: bool
) -> None:
    for action in actions:
        if dry_run:
            print(f"[dry-run] {action.describe()}")
            continue
        if action.kind == "create":
            rel = f"{cfg.root}/{action.title}"
            cli.create_from_template(
                TEMPLATES.get(action.note_type, TEMPLATES["atomic"]),
                rel,
                action.open_file,
            )
            cli.set_tags(rel, action.tags)
        elif action.kind == "add_tags":
            path = cfg.vault_root / f"{action.title}.md"
            current = read_frontmatter(path).get("tags", [])
            merged = current + [t for t in action.tags if t not in current]
            cli.set_tags(f"{cfg.root}/{action.title}", merged)
        print(f"  {action.describe()}")


def cmd_create(
    cfg: Config,
    note_type: str,
    title: str,
    tag_path: str,
    open_file: bool,
    chain: bool,
    dry_run: bool,
    encrypt: bool,
    extra_tags: list[str],
) -> int:
    live = scan_vault(cfg)
    actions = plan_topic(cfg, live["topics"], tag_path, chain)

    leaf_tags = [tag_path.strip("/")] + extra_tags
    if dry_run:
        for action in actions:
            print(f"[dry-run] {action.describe()}")
        print(
            f"[dry-run] create {note_type} note '{title}' tags=[{', '.join(leaf_tags)}]"
            + (", open in UI" if open_file else "")
        )
        return 0

    if not ObsidianCli(cfg).app_running():
        print(
            "note: Obsidian not open; index-notes blocks render when the app next opens",
            file=sys.stderr,
        )

    cli = ObsidianCli(cfg)
    _execute(cfg, cli, actions, dry_run=False)
    rel = f"{cfg.root}/{title}"
    cli.create_from_template(
        TEMPLATES.get(note_type, TEMPLATES["atomic"]), rel, open_file
    )
    cli.set_tags(rel, leaf_tags)
    print(
        f"  create {note_type} note '{title}' tags=[{', '.join(leaf_tags)}]"
        + (", open in UI" if open_file else "")
    )

    save_store(cfg, scan_vault(cfg), encrypt)
    return 0


def cmd_ensure(cfg: Config, tag_path: str, dry_run: bool, encrypt: bool) -> int:
    live = scan_vault(cfg)
    actions = plan_topic(cfg, live["topics"], tag_path, chain=True)
    _execute(cfg, ObsidianCli(cfg), actions, dry_run)
    if not dry_run:
        save_store(cfg, scan_vault(cfg), encrypt)
    return 0


# --------------------------------------------------------------------------
# CLI


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="obsidian_vault",
        description=__doc__.splitlines()[0],
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sync = sub.add_parser("sync", help="rebuild the store from a vault scan")
    sync.add_argument("--no-encrypt", action="store_true", help="skip the .gpg copy")

    dump = sub.add_parser("dump", help="print the tag-tree store")
    dump.add_argument("--raw", action="store_true", help="print raw JSON")

    sub.add_parser("status", help="show config and store state")

    create = sub.add_parser(
        "create", help="bootstrap a new note (infer index chain first)"
    )
    create.add_argument("note_type", choices=sorted(TEMPLATES))
    create.add_argument(
        "title", help="human title / filename (e.g. 'Generating an EdDSA SSH Key')"
    )
    create.add_argument(
        "--tag",
        dest="tag_path",
        required=True,
        help="leaf topic tag path (e.g. Technology/Systems/Security/GPG-Keys)",
    )
    create.add_argument(
        "--tags", dest="extra_tags", nargs="*", default=[], help="extra leaf tags"
    )
    create.add_argument(
        "--open",
        dest="open_file",
        action="store_true",
        help="open the created note in the UI",
    )
    create.add_argument(
        "--no-open",
        dest="open_file",
        action="store_false",
        help="do not open the created note (default)",
    )
    create.set_defaults(open_file=False)
    create.add_argument(
        "--no-chain", action="store_true", help="skip ancestor index notes"
    )
    create.add_argument("--dry-run", action="store_true", help="print the plan only")
    create.add_argument("--no-encrypt", action="store_true")

    ensure = sub.add_parser(
        "ensure-topic", help="create only the missing index chain for a topic"
    )
    ensure.add_argument("tag_path")
    ensure.add_argument("--dry-run", action="store_true")
    ensure.add_argument("--no-encrypt", action="store_true")

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    cfg = Config()

    if args.command == "sync":
        return cmd_sync(cfg, not args.no_encrypt)
    if args.command == "dump":
        return cmd_dump(cfg, args.raw)
    if args.command == "status":
        return cmd_status(cfg)
    if args.command == "create":
        return cmd_create(
            cfg,
            args.note_type,
            args.title,
            args.tag_path,
            args.open_file,
            chain=not args.no_chain,
            dry_run=args.dry_run,
            encrypt=not args.no_encrypt,
            extra_tags=args.extra_tags,
        )
    if args.command == "ensure-topic":
        return cmd_ensure(cfg, args.tag_path, args.dry_run, not args.no_encrypt)
    return 2


if __name__ == "__main__":
    sys.exit(main())
