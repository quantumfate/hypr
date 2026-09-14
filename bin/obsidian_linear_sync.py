#!/usr/bin/env python3
"""Mirror Linear projects, milestones and issues into the Zettelkasten.

Linear is the source of truth; the sync is strictly one-way and never deletes.
The Linear hierarchy becomes an index-notes tag tree, so the plugin renders the
whole structure without either script knowing about the other:

    Projects/<Project>/meta_idx                          project note
    Projects/<Project>/<Milestone>/meta_idx              milestone note
    Projects/<Project>/<Milestone>/<IDENT>/idx           issue in a milestone
    Projects/<Project>/<IDENT>/idx                       issue with no milestone
    Projects/<Project>/<Milestone>/<PARENT>/<IDENT>/idx  sub-issue
    Projects/<Project>/.../<IDENT>                       your notes (you tag them)

Milestones are optional at every level: a project without them holds its issues
directly, and an issue loses or gains a milestone by being re-tagged in place.

A sub-issue is filed under its parent rather than its own milestone, so the
sub-issue tree stays navigable. Its milestone note still lists it, through a
Dataview query over linear_milestone_id rather than a second index block:
index-notes derives a block's anchor from the topic path, so one note cannot
render both an idx and a meta_idx block for the same topic.

Issues with no Linear project are skipped: assigning a project is the gesture
that pulls an issue into the vault.

Ownership inside a note is narrow. The `linear_*` frontmatter keys and the
`%% linear:begin %%` block belong to the sync; everything else belongs to you
and is never rewritten. Filenames are frozen at creation so a title change in
Linear cannot break an inbound wikilink.

Dry-run by default; pass --apply to write.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from obsidian_vault import (
    TEMPLATES,
    Config,
    ObsidianCli,
    read_frontmatter,
    save_store,
    scan_vault,
)

API_URL = "https://api.linear.app/graphql"
WEB_PREFIX = "https://linear.app/"
APP_PREFIX = "linear://"  # registered to linear-bin.desktop
PAGE_SIZE = 100
PROJECTS_TAG = "Projects"

PASS_VAULT = os.environ.get("LINEAR_PASS_VAULT", "Productivity")
PASS_ITEM = os.environ.get("LINEAR_PASS_ITEM", "linear.app")
PASS_FIELD = os.environ.get("LINEAR_PASS_FIELD", "api_key")

BLOCK_START = "%% linear:begin %%"
BLOCK_END = "%% linear:end %%"

STATUS_ICONS = {
    "backlog": "🗒️",
    "unstarted": "📋",
    "started": "🔄",
    "completed": "✅",
    "canceled": "❌",
    "paused": "⏸️",
    "planned": "📋",
}

ISSUES_QUERY = """
query Issues($after: String) {
  issues(first: PAGE, after: $after, includeArchived: true) {
    pageInfo { hasNextPage endCursor }
    nodes {
      id identifier title description url
      priority estimate createdAt updatedAt archivedAt dueDate
      state { name type }
      assignee { displayName }
      team { key name }
      labels { nodes { name } }
      project { id name }
      projectMilestone { id name }
      parent { identifier title }
    }
  }
}
""".replace("PAGE", str(PAGE_SIZE))

PROJECTS_QUERY = """
query Projects($after: String) {
  projects(first: PAGE, after: $after, includeArchived: true) {
    pageInfo { hasNextPage endCursor }
    nodes {
      id name description content url
      state startDate targetDate updatedAt
      lead { displayName }
    }
  }
}
""".replace("PAGE", str(PAGE_SIZE))

# Milestones are fetched flat rather than nested under projects: Linear rejects
# the nested form as "Query too complex" once both pages are 100 wide.
MILESTONES_QUERY = """
query Milestones($after: String) {
  projectMilestones(first: PAGE, after: $after) {
    pageInfo { hasNextPage endCursor }
    nodes {
      id name description targetDate sortOrder updatedAt
      project { id }
    }
  }
}
""".replace("PAGE", str(PAGE_SIZE))


# --------------------------------------------------------------------------
# Credential


class AuthError(RuntimeError):
    """Proton Pass could not hand over the API key."""


def notify(title: str, body: str, urgency: str = "critical") -> None:
    """Best-effort desktop notification; a headless run must not fail on this."""
    try:
        subprocess.run(
            [
                "notify-send",
                "-u",
                urgency,
                "-i",
                "dialog-password",
                "-t",
                "0",
                title,
                body,
            ],
            check=False,
            capture_output=True,
        )
    except FileNotFoundError:
        pass


def read_api_key() -> str:
    """Pull the key out of Proton Pass. Never written to disk, never logged."""
    env_key = os.environ.get("LINEAR_API_KEY")
    if env_key:
        return env_key.strip()

    try:
        proc = subprocess.run(
            [
                "pass-cli",
                "item",
                "view",
                "--vault-name",
                PASS_VAULT,
                "--item-title",
                PASS_ITEM,
                "--output=json",
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=20,
        )
    except FileNotFoundError as exc:
        raise AuthError("pass-cli is not installed") from exc
    except subprocess.TimeoutExpired as exc:
        raise AuthError("pass-cli timed out") from exc

    if proc.returncode != 0 or not proc.stdout.strip():
        # A forced logout prints to stdout and still exits non-zero; either way
        # the recovery is the same interactive login.
        raise AuthError(
            (proc.stderr or proc.stdout).strip().splitlines()[-1:] or ["no session"]
        )

    try:
        item = json.loads(proc.stdout)["item"]["content"]
    except (json.JSONDecodeError, KeyError) as exc:
        raise AuthError("unexpected pass-cli output shape") from exc

    for field in item.get("extra_fields", []):
        if field.get("name") == PASS_FIELD:
            value = field.get("content", {}).get("Hidden", "")
            if value:
                return value.strip()
    raise AuthError(f"item {PASS_ITEM!r} has no {PASS_FIELD!r} field")


# --------------------------------------------------------------------------
# Linear API


def graphql(key: str, query: str, variables: dict) -> dict:
    request = urllib.request.Request(
        API_URL,
        data=json.dumps({"query": query, "variables": variables}).encode(),
        headers={"Authorization": key, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as exc:
        if exc.code in (401, 403):
            raise AuthError(f"Linear rejected the API key (HTTP {exc.code})") from exc
        raise RuntimeError(f"Linear API error: HTTP {exc.code}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Linear unreachable: {exc.reason}") from exc

    if payload.get("errors"):
        raise RuntimeError(f"Linear API error: {payload['errors'][0].get('message')}")
    return payload["data"]


def fetch_all(key: str, query: str, root: str) -> list[dict]:
    """Walk a connection to the end of its cursor."""
    nodes: list[dict] = []
    after = None
    while True:
        page = graphql(key, query, {"after": after})[root]
        nodes.extend(page["nodes"])
        if not page["pageInfo"]["hasNextPage"]:
            return nodes
        after = page["pageInfo"]["endCursor"]


def desktop_url(web_url: str) -> str:
    """Deep link that opens the Linear desktop app instead of a browser tab."""
    if web_url.startswith(WEB_PREFIX):
        return APP_PREFIX + web_url[len(WEB_PREFIX) :]
    return web_url


# --------------------------------------------------------------------------
# Naming

INVALID_FILENAME = re.compile(r'[<>:"/\\|?*\x00-\x1f]')
SLUG_STRIP = re.compile(r"[^\w\- ]+")


def slug(name: str) -> str:
    """Name to tag segment, preserving case so humanize() round-trips."""
    cleaned = SLUG_STRIP.sub("", name).strip()
    cleaned = re.sub(r"[\s_]+", "-", cleaned)
    return re.sub(r"-{2,}", "-", cleaned).strip("-")


def safe_title(name: str) -> str:
    """A filename stem Obsidian and the filesystem both accept."""
    return re.sub(r"\s{2,}", " ", INVALID_FILENAME.sub("", name).strip())


def issue_title(issue: dict) -> str:
    """Frozen at creation: identifier first so notes sort and grep by it."""
    return f"{issue['identifier']} {safe_title(issue['title'])}".strip()


def milestone_topic(issue: dict) -> str | None:
    """The milestone's own topic path, independent of where the issue is filed."""
    milestone = issue.get("projectMilestone")
    if not milestone:
        return None
    return f"{PROJECTS_TAG}/{slug(issue['project']['name'])}/{slug(milestone['name'])}"


def issue_topic(
    issue: dict, by_ident: dict[str, dict], seen: frozenset = frozenset()
) -> str:
    """Where an issue hangs: under its parent issue, else its milestone, else the project.

    Parent wins over milestone so the sub-issue tree stays navigable; the
    milestone is preserved separately as a leaf tag by `issue_tags`.
    """
    parent = issue.get("parent")
    ident = issue["identifier"]
    if parent and parent["identifier"] not in seen and parent["identifier"] in by_ident:
        base = issue_topic(by_ident[parent["identifier"]], by_ident, seen | {ident})
        return f"{base}/{ident}"

    parts = [PROJECTS_TAG, slug(issue["project"]["name"])]
    milestone = milestone_topic(issue)
    if milestone:
        parts.append(milestone.rpartition("/")[2])
    parts.append(ident)
    return "/".join(parts)


def issue_tags(issue: dict, by_ident: dict[str, dict], parents: set[str]) -> list[str]:
    """Index tags for an issue note, most specific first.

    A parent also carries meta_idx so index-notes lists its children, which are
    index notes rather than leaves. The milestone is not a tag: a sub-issue is
    filed under its parent, and the milestone note finds it by Dataview query
    over linear_milestone_id instead.
    """
    topic = issue_topic(issue, by_ident)
    tags = [f"{topic}/idx"]
    if issue["identifier"] in parents:
        tags.append(f"{topic}/meta_idx")
    return tags


def status_icon(kind: str) -> str:
    return STATUS_ICONS.get(kind or "", "•")


# --------------------------------------------------------------------------
# Note content

FRONTMATTER_RE = re.compile(r"^(---\n)(.*?)(\n---\n)", re.DOTALL)
H1_RE = re.compile(r"^#\s+\S", re.MULTILINE)


def scalar(value) -> str:
    """Frontmatter values are written raw, so keep them to one safe line."""
    text = str(value if value is not None else "").replace("\n", " ").strip()
    return text


HEADING_RE = re.compile(r"^(#{1,6})(\s+\S)")
FENCE_RE = re.compile(r"^\s*(```|~~~)")
MIN_SYNCED_LEVEL = 3


def demote_headings(markdown: str) -> str:
    """Push synced headings below H2 so the note keeps its own first H2.

    The index normalizer parks `^indexof-*` callouts directly above the first
    H2. A Linear description that opens with `## Purpose` would therefore pull
    the index block inside the managed region, where the next sync deletes it
    and the plugin regenerates it — churning on every tick.
    """
    lines = markdown.split("\n")
    in_fence = False
    levels = []
    for line in lines:
        if FENCE_RE.match(line):
            in_fence = not in_fence
        elif not in_fence and (m := HEADING_RE.match(line)):
            levels.append(len(m.group(1)))
    if not levels or min(levels) >= MIN_SYNCED_LEVEL:
        return markdown

    shift = MIN_SYNCED_LEVEL - min(levels)
    out, in_fence = [], False
    for line in lines:
        if FENCE_RE.match(line):
            in_fence = not in_fence
        elif not in_fence and (m := HEADING_RE.match(line)):
            level = min(len(m.group(1)) + shift, 6)
            line = "#" * level + m.group(2) + line[m.end() :]
        out.append(line)
    return "\n".join(out)


def issue_fields(issue: dict) -> dict:
    """The frontmatter keys this script owns on an issue note."""
    milestone = issue.get("projectMilestone") or {}
    labels = [n["name"] for n in (issue.get("labels") or {}).get("nodes", [])]
    fields = {
        "linear_kind": "issue",
        "linear_id": issue["id"],
        "linear_identifier": issue["identifier"],
        "linear_url": issue["url"],
        "linear_app_url": desktop_url(issue["url"]),
        "linear_status": scalar((issue.get("state") or {}).get("name")),
        "linear_state_type": scalar((issue.get("state") or {}).get("type")),
        "linear_assignee": scalar((issue.get("assignee") or {}).get("displayName")),
        "linear_team": scalar((issue.get("team") or {}).get("name")),
        "linear_project": scalar(issue["project"]["name"]),
        "linear_project_id": issue["project"]["id"],
        "linear_milestone": scalar(milestone.get("name")),
        "linear_milestone_id": scalar(milestone.get("id")),
        "linear_parent": scalar((issue.get("parent") or {}).get("identifier")),
        "linear_priority": scalar(issue.get("priority", 0) or 0),
        "linear_estimate": scalar(issue.get("estimate")),
        "linear_due": scalar(issue.get("dueDate")),
        "linear_labels": ", ".join(labels),
        "linear_created": scalar(issue.get("createdAt")),
        "linear_updated": scalar(issue.get("updatedAt")),
        "linear_last_synced": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    if issue.get("archivedAt"):
        fields["linear_archived"] = "true"
    return fields


def project_fields(project: dict) -> dict:
    """The frontmatter keys this script owns on a project note."""
    return {
        "linear_kind": "project",
        "linear_project_id": project["id"],
        "linear_project": scalar(project["name"]),
        "linear_url": project.get("url", ""),
        "linear_app_url": desktop_url(project.get("url", "")),
        "linear_status": scalar(project.get("state")),
        "linear_lead": scalar((project.get("lead") or {}).get("displayName")),
        "linear_start": scalar(project.get("startDate")),
        "linear_target": scalar(project.get("targetDate")),
        "linear_updated": scalar(project.get("updatedAt")),
        "linear_last_synced": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }


def milestone_fields(milestone: dict, project: dict) -> dict:
    """The frontmatter keys this script owns on a milestone note."""
    return {
        "linear_kind": "milestone",
        "linear_milestone_id": milestone["id"],
        "linear_milestone": scalar(milestone["name"]),
        "linear_project": scalar(project["name"]),
        "linear_project_id": project["id"],
        "linear_target": scalar(milestone.get("targetDate")),
        "linear_updated": scalar(milestone.get("updatedAt")),
        "linear_last_synced": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }


def merge_frontmatter(text: str, fields: dict) -> str:
    """Replace the linear_* keys in place, appending any that are new.

    Untouched keys keep their position, so a Templater-written header and any
    property the user added by hand survive verbatim.
    """
    match = FRONTMATTER_RE.match(text)
    if not match:
        block = "".join(f"{k}: {v}\n" for k, v in fields.items())
        return f"---\n{block}---\n\n{text}"

    remaining = dict(fields)
    out = []
    for line in match.group(2).split("\n"):
        key = re.match(r"^(\w+):", line)
        name = key.group(1) if key else None
        if name in remaining:
            out.append(f"{name}: {remaining.pop(name)}")
        else:
            out.append(line)
    out.extend(f"{k}: {v}" for k, v in remaining.items())
    return f"{match.group(1)}{chr(10).join(out)}{match.group(3)}{text[match.end() :]}"


def issue_block(issue: dict) -> str:
    """Status callout plus the issue's Linear description, as one managed region."""
    state = (issue.get("state") or {}).get("name", "Unknown")
    kind = (issue.get("state") or {}).get("type", "")
    assignee = (issue.get("assignee") or {}).get("displayName") or "unassigned"
    milestone = (issue.get("projectMilestone") or {}).get("name")

    summary = f"> [!info] {status_icon(kind)} {state} · {assignee}"
    if milestone:
        summary += f" · {milestone}"

    lines = [
        BLOCK_START,
        summary,
        f"> [Open {issue['identifier']} in Linear]({desktop_url(issue['url'])})",
    ]
    parent = issue.get("parent")
    if parent:
        lines.append(f"> Sub-issue of {parent['identifier']}: {parent['title']}")

    description = (issue.get("description") or "").strip()
    if description:
        lines += ["", demote_headings(description)]
    lines.append(BLOCK_END)
    return "\n".join(lines)


def project_block(project: dict) -> str:
    """Properties, summary and the project's long-form content."""
    state = project.get("state") or "unknown"
    lead = (project.get("lead") or {}).get("displayName") or "unassigned"

    summary = f"> [!info] {status_icon(state)} {state.capitalize()} · {lead}"
    if project.get("targetDate"):
        summary += f" · target {project['targetDate']}"

    lines = [
        BLOCK_START,
        summary,
        f"> [Open project in Linear]({desktop_url(project.get('url', ''))})",
    ]

    for part in (project.get("description"), project.get("content")):
        if (part or "").strip():
            lines += ["", demote_headings(part.strip())]
    lines.append(BLOCK_END)
    return "\n".join(lines)


def milestone_block(milestone: dict, project: dict) -> str:
    """Target, description, and a Dataview roster of every issue in the milestone.

    The roster cannot be an index-notes block: that plugin derives a block's
    anchor from the topic path, so a note tagged both `X/idx` and `X/meta_idx`
    produces two blocks claiming `^indexof-X` and only one survives. A query
    also catches sub-issues, which are filed under their parent rather than here.
    """
    summary = f"> [!info] ◇ Milestone of {project['name']}"
    if milestone.get("targetDate"):
        summary += f" · target {milestone['targetDate']}"

    lines = [BLOCK_START, summary]
    description = (milestone.get("description") or "").strip()
    if description:
        lines += ["", demote_headings(description)]

    lines += [
        "",
        "```dataview",
        "TABLE WITHOUT ID file.link AS Issue, linear_status AS Status, linear_parent AS Parent",
        'FROM "Zettelkasten"',
        f'WHERE linear_milestone_id = "{milestone["id"]}"',
        "SORT linear_identifier ASC",
        "```",
    ]
    lines.append(BLOCK_END)
    return "\n".join(lines)


def merge_block(text: str, block: str) -> str:
    """Replace the delimited block, or plant it directly under the H1.

    The normalizer parks `^indexof-*` callouts just above the first H2, so a
    block written here always ends up above the index block. That is the agreed
    layout and needs no coordination between the two scripts.
    """
    start = text.find(BLOCK_START)
    end = text.find(BLOCK_END)
    if start != -1 and end > start:
        return text[:start] + block + text[end + len(BLOCK_END) :]

    h1 = H1_RE.search(text)
    if not h1:
        return f"{text.rstrip()}\n\n{block}\n"
    line_end = text.find("\n", h1.start())
    line_end = len(text) if line_end == -1 else line_end
    return f"{text[:line_end]}\n\n{block}\n{text[line_end:]}"


def render_title(text: str, title: str) -> str:
    """Track the Linear title in the H1 without ever touching the filename."""
    h1 = H1_RE.search(text)
    if not h1:
        return text
    line_end = text.find("\n", h1.start())
    line_end = len(text) if line_end == -1 else line_end
    return text[: h1.start()] + f"# {title}" + text[line_end:]


def write_note(path: Path, title: str, fields: dict, block: str) -> None:
    text = path.read_text(encoding="utf-8")
    text = merge_frontmatter(text, fields)
    text = render_title(text, title)
    path.write_text(merge_block(text, block), encoding="utf-8")


# --------------------------------------------------------------------------
# Planning


class Create:
    """A note to bring into being, with the content to write once it exists."""

    def __init__(
        self, title: str, tags: list[str], fields: dict, block: str, heading: str
    ) -> None:
        self.title = title
        self.tags = tags
        self.fields = fields
        self.block = block
        self.heading = heading


class Update:
    """An existing note whose managed region has drifted from Linear."""

    def __init__(
        self,
        path: Path,
        fields: dict,
        block: str,
        heading: str,
        retag: list[str] | None = None,
    ) -> None:
        self.path = path
        self.fields = fields
        self.block = block
        self.heading = heading
        self.retag = retag


class Plan:
    def __init__(self) -> None:
        self.creates: list[Create] = []
        self.updates: list[Update] = []
        self.orphans: list[Path] = []
        self.migrations: list[tuple[str, str]] = []
        self.topics: dict[str, str] = {}
        self.unchanged = 0
        self.skipped_no_project = 0

    def empty(self) -> bool:
        return not (self.creates or self.updates or self.orphans or self.migrations)


# --------------------------------------------------------------------------
# Hierarchy snapshot
#
# Tags are derived from Linear's naming hierarchy, so renaming a project or
# moving an issue changes the tag path. The sync retags its own notes by id,
# but your notes tagged into that tree are outside its knowledge and would keep
# a dead path. Recording the previous hierarchy lets the next run diff old
# against new and rename the prefix wherever it appears.

HIERARCHY_VERSION = 1


def hierarchy_path(cfg: Config) -> Path:
    return cfg.store_dir / "linear.json"


def load_hierarchy(cfg: Config) -> dict:
    """The topics as of the last successful apply; empty on a first run."""
    path = hierarchy_path(cfg)
    if not path.exists():
        return {}
    try:
        stored = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}
    return (
        stored.get("topics", {}) if stored.get("version") == HIERARCHY_VERSION else {}
    )


def save_hierarchy(cfg: Config, topics: dict[str, str], previous: dict) -> None:
    """Merge this run's topics over the stored ones; a filtered run sees only part."""
    merged = {**previous, **topics}
    hierarchy_path(cfg).parent.mkdir(parents=True, exist_ok=True)
    hierarchy_path(cfg).write_text(
        json.dumps(
            {
                "version": HIERARCHY_VERSION,
                "generated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                "topics": merged,
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )


def plan_migrations(
    previous: dict[str, str], current: dict[str, str]
) -> list[tuple[str, str]]:
    """Topic paths that moved since the last run, deepest first.

    Deepest first so a nested rename is applied before the ancestor rename that
    would otherwise rewrite its prefix out from under it.
    """
    moved = [
        (old, current[key])
        for key, old in previous.items()
        if key in current and current[key] != old
    ]

    # Renaming one milestone moves every issue beneath it, and each of those
    # reads as its own move. Keeping only the shallowest rename that explains a
    # descendant turns 127 lines into the one rename that actually happened.
    def implied(old: str, new: str) -> bool:
        return any(
            old.startswith(f"{ancestor}/")
            and new == retag_prefix(old, ancestor, target)
            for ancestor, target in moved
            if ancestor != old
        )

    kept = [(old, new) for old, new in moved if not implied(old, new)]
    return sorted(kept, key=lambda pair: pair[0].count("/"), reverse=True)


def retag_prefix(tag: str, old: str, new: str) -> str:
    """Rewrite a tag that is, or sits beneath, a renamed topic."""
    if tag == old:
        return new
    return new + tag[len(old) :] if tag.startswith(f"{old}/") else tag


def notes_by_key(cfg: Config, key: str, kind: str) -> dict[str, Path]:
    """Existing synced notes of one kind, indexed by their Linear id."""
    found: dict[str, Path] = {}
    for path in cfg.vault_root.rglob("*.md"):
        fm = read_frontmatter(path)
        value = fm.get(key)
        if value and note_kind(fm) == kind:
            found.setdefault(value, path)
    return found


def note_kind(fm: dict) -> str | None:
    """What a synced note represents.

    An issue note also carries linear_project_id, so the id alone cannot say
    what a note is. Notes written before linear_kind existed are issues, which
    linear_identifier identifies.
    """
    declared = fm.get("linear_kind")
    if declared:
        return declared
    return "issue" if fm.get("linear_identifier") else None


def synced_tags(fm: dict) -> list[str]:
    """The Projects/... tags this script owns on a note; the rest are yours."""
    return [t for t in fm.get("tags", []) if t.startswith(f"{PROJECTS_TAG}/")]


def plan_note(
    plan: Plan,
    path: Path | None,
    title: str,
    tags: list[str],
    fields: dict,
    block: str,
    stamp: str,
    force: bool = False,
    heading: str | None = None,
) -> None:
    """Queue a create or an update, skipping notes Linear has not moved.

    `title` is the filename stem, frozen at creation; `heading` is the H1, which
    tracks the Linear title. For issues they differ: the stem carries the
    identifier so notes sort and grep by it, the H1 does not repeat it.
    """
    heading = heading or title
    if path is None:
        plan.creates.append(Create(title, tags, fields, block, heading))
        return

    fm = read_frontmatter(path)
    retag = tags if set(synced_tags(fm)) != set(tags) else None
    if fm.get("linear_updated") == stamp and retag is None and not force:
        plan.unchanged += 1
        return
    plan.updates.append(Update(path, fields, block, heading, retag))


def build_plan(
    cfg: Config,
    projects: list[dict],
    milestones: list[dict],
    issues: list[dict],
    only: str | None = None,
    force: bool = False,
) -> Plan:
    plan = Plan()
    topics_now: dict[str, str] = {}
    milestones_by_project: dict[str, list[dict]] = {}
    for milestone in sorted(milestones, key=lambda m: m.get("sortOrder") or 0):
        milestones_by_project.setdefault(milestone["project"]["id"], []).append(
            milestone
        )
    store = scan_vault(cfg)
    topics = store["topics"]
    project_notes = notes_by_key(cfg, "linear_project_id", "project")
    milestone_notes = notes_by_key(cfg, "linear_milestone_id", "milestone")
    issue_notes = notes_by_key(cfg, "linear_id", "issue")

    wanted_projects = {p["id"] for p in projects}
    if only:
        wanted_projects = {
            p["id"]
            for p in projects
            if only.lower() in (p["name"].lower(), slug(p["name"]).lower())
        }

    def existing(
        by_id: dict[str, Path], key: str, topic: str, suffix: str
    ) -> Path | None:
        """Prefer the id match; fall back to whatever already owns the tag."""
        if key in by_id:
            return by_id[key]
        field = "meta_idx_note" if suffix == "meta_idx" else "idx_note"
        title = topics.get(topic, {}).get(field)
        return cfg.vault_root / f"{title}.md" if title else None

    for project in projects:
        if project["id"] not in wanted_projects:
            continue
        topic = f"{PROJECTS_TAG}/{slug(project['name'])}"
        topics_now[f"project:{project['id']}"] = topic
        plan_note(
            plan,
            existing(project_notes, project["id"], topic, "meta_idx"),
            safe_title(project["name"]),
            [f"{topic}/meta_idx"],
            project_fields(project),
            project_block(project),
            scalar(project.get("updatedAt")),
            force,
        )

        for milestone in milestones_by_project.get(project["id"], []):
            ms_topic = f"{topic}/{slug(milestone['name'])}"
            topics_now[f"milestone:{milestone['id']}"] = ms_topic
            plan_note(
                plan,
                existing(milestone_notes, milestone["id"], ms_topic, "meta_idx"),
                safe_title(milestone["name"]),
                [f"{ms_topic}/meta_idx"],
                milestone_fields(milestone, project),
                milestone_block(milestone, project),
                scalar(milestone.get("updatedAt")),
                force,
            )

    by_ident = {i["identifier"]: i for i in issues if i.get("project")}
    parents = {i["parent"]["identifier"] for i in issues if i.get("parent")}

    seen: set[str] = set()
    for issue in issues:
        project = issue.get("project")
        if not project or not project.get("name"):
            plan.skipped_no_project += 1
            continue
        if project["id"] not in wanted_projects:
            continue
        seen.add(issue["id"])
        topics_now[f"issue:{issue['id']}"] = issue_topic(issue, by_ident)
        plan_note(
            plan,
            issue_notes.get(issue["id"]),
            issue_title(issue),
            issue_tags(issue, by_ident, parents),
            issue_fields(issue),
            issue_block(issue),
            scalar(issue.get("updatedAt")),
            force,
            heading=safe_title(issue["title"]),
        )

    # A filtered run has only seen part of Linear, so it cannot judge orphans.
    for linear_id, path in issue_notes.items() if not only else []:
        if (
            linear_id in seen
            or read_frontmatter(path).get("linear_state") == "orphaned"
        ):
            continue
        plan.orphans.append(path)

    plan.migrations = plan_migrations(load_hierarchy(cfg), topics_now)
    plan.topics = topics_now
    return plan


# --------------------------------------------------------------------------
# Execution


def describe(plan: Plan) -> None:
    for old, new in plan.migrations:
        print(f"  move    {old}  ->  {new}")
    for create in plan.creates:
        print(f"  create  {create.title}  [{create.tags[0]}]")
    for update in plan.updates:
        note = f"  update  {update.path.name}"
        print(f"{note}  -> {update.retag[0]}" if update.retag else note)
    for path in plan.orphans:
        print(f"  orphan  {path.name}")
    if plan.unchanged:
        print(f"  {plan.unchanged} note(s) unchanged since last sync")
    if plan.skipped_no_project:
        print(f"  skipped {plan.skipped_no_project} issue(s) with no Linear project")


def migrate_tags(
    cfg: Config, cli: ObsidianCli, migrations: list[tuple[str, str]]
) -> int:
    """Rename moved topic prefixes on every note that carries them.

    Runs before anything else so the rest of the plan sees the new paths. This
    is the only place the sync touches notes it did not create: your own notes
    tagged into the tree would otherwise keep a path Linear no longer has.
    """
    touched = 0
    for path in sorted(cfg.vault_root.rglob("*.md")):
        tags = read_frontmatter(path).get("tags", [])
        if not tags:
            continue
        renamed = list(tags)
        for old, new in migrations:
            renamed = [retag_prefix(tag, old, new) for tag in renamed]
        if renamed == tags:
            continue
        cli.set_tags(f"{cfg.root}/{path.stem}", renamed)
        print(f"  retag   {path.name}")
        touched += 1
    return touched


def apply_plan(cfg: Config, plan: Plan) -> None:
    cli = ObsidianCli(cfg)
    needs_app = plan.creates or plan.migrations or any(u.retag for u in plan.updates)
    if needs_app and not cli.app_running():
        raise RuntimeError(
            "Obsidian is not running; note creation needs Templater via its CLI"
        )

    if plan.migrations:
        for old, new in plan.migrations:
            print(f"  move    {old}  ->  {new}")
        migrate_tags(cfg, cli, plan.migrations)

    for create in plan.creates:
        target = cfg.vault_root / f"{create.title}.md"
        if target.exists():
            # No merge logic by design: move the stranger aside and start clean.
            aside = cfg.vault_root / f"{create.title} (pre-linear).md"
            target.rename(aside)
            print(f"  moved   {target.name} -> {aside.name}")
        rel = f"{cfg.root}/{create.title}"
        cli.create_from_template(TEMPLATES["moc"], rel, open_file=False)
        cli.set_tags(rel, create.tags)
        write_note(target, create.heading, create.fields, create.block)
        print(f"  create  {create.title}")

    for update in plan.updates:
        if update.retag:
            fm = read_frontmatter(update.path)
            owned = set(synced_tags(fm))
            kept = [t for t in fm.get("tags", []) if t not in owned]
            cli.set_tags(f"{cfg.root}/{update.path.stem}", [*update.retag, *kept])
        write_note(update.path, update.heading, update.fields, update.block)
        print(f"  update  {update.path.name}")

    for path in plan.orphans:
        text = path.read_text(encoding="utf-8")
        path.write_text(
            merge_frontmatter(
                text,
                {
                    "linear_state": "orphaned",
                    "linear_orphaned_at": datetime.now(timezone.utc).date().isoformat(),
                },
            ),
            encoding="utf-8",
        )
        print(f"  orphan  {path.name}")


def cmd_sync(
    cfg: Config,
    apply: bool,
    encrypt: bool,
    only: str | None = None,
    force: bool = False,
) -> int:
    key = read_api_key()
    projects = fetch_all(key, PROJECTS_QUERY, "projects")
    milestones = fetch_all(key, MILESTONES_QUERY, "projectMilestones")
    issues = fetch_all(key, ISSUES_QUERY, "issues")
    plan = build_plan(cfg, projects, milestones, issues, only, force)

    print(
        f"{len(projects)} project(s), {len(milestones)} milestone(s), "
        f"{len(issues)} issue(s) from Linear"
    )
    if plan.empty():
        describe(plan)
        if apply:
            save_hierarchy(cfg, plan.topics, load_hierarchy(cfg))
        print("nothing to do")
        return 0

    if not apply:
        describe(plan)
        pending = (
            len(plan.creates)
            + len(plan.updates)
            + len(plan.orphans)
            + len(plan.migrations)
        )
        print(f"\n{pending} change(s) planned. Re-run with --apply.", file=sys.stderr)
        return 0

    apply_plan(cfg, plan)
    save_hierarchy(cfg, plan.topics, load_hierarchy(cfg))
    save_store(cfg, scan_vault(cfg), encrypt)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="obsidian_linear_sync",
        description=__doc__.splitlines()[0],
    )
    parser.add_argument(
        "--apply", action="store_true", help="write changes (default: dry run)"
    )
    parser.add_argument(
        "--no-encrypt", action="store_true", help="skip the tags.json.gpg copy"
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="rewrite managed regions even when Linear reports no change",
    )
    parser.add_argument(
        "--project",
        metavar="NAME",
        help="only sync this Linear project (name or slug); skips orphan checks",
    )
    args = parser.parse_args(argv)

    cfg = Config()
    try:
        return cmd_sync(
            cfg,
            args.apply,
            encrypt=not args.no_encrypt,
            only=args.project,
            force=args.force,
        )
    except AuthError as exc:
        notify(
            "Linear sync: Proton Pass locked",
            "Obsidian cannot reach Linear.\nRecover with:  pass-cli login --interactive",
        )
        print(f"auth: {exc}", file=sys.stderr)
        print("recover with: pass-cli login --interactive", file=sys.stderr)
        return 2
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
