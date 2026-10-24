#!/usr/bin/env python3
"""Print the public service components of the Claude or OpenAI status page.

The official CLI reports only the overall status. Both pages publish their
component lists without authentication, so this helper reads one fixed feed
per provider and prints a bounded record. Remote prose other than component
names is never emitted.
"""
import argparse
import json
import re
import urllib.request

# incident.io serves OpenAI's grouped native feed; Claude uses Atlassian Statuspage.
FEEDS = {
    "claude": ("statuspage", "https://status.claude.com/api/v2/components.json"),
    "openai": ("incidentio", "https://status.openai.com/proxy/status.openai.com"),
}
MAXIMUM_BYTES = 1024 * 1024
MAXIMUM_COMPONENTS = 64
MAXIMUM_NAME = 120
# Matches the upstream CodexBar mapping to the CLI's status indicator values.
INDICATORS = {
    "operational": "none",
    "degraded_performance": "minor",
    "partial_outage": "major",
    "major_outage": "critical",
    "full_outage": "critical",
    "under_maintenance": "maintenance",
}
RANK = ["none", "maintenance", "unknown", "minor", "major", "critical"]


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def name_text(value):
    if not isinstance(value, str):
        return ""
    return re.sub(r"[\x00-\x1f\x7f]+", " ", value).strip()[:MAXIMUM_NAME].strip()


def row(name, status, children=()):
    return {"name": name, "indicator": INDICATORS.get(status, "unknown"), "children": list(children)}


def worst(children):
    return max((child["indicator"] for child in children), key=RANK.index, default="none")


def parse_statuspage(payload):
    components = [c for c in payload["components"]
                  if isinstance(c, dict) and isinstance(c.get("id"), str) and name_text(c.get("name"))]
    components.sort(key=lambda c: c.get("position") if isinstance(c.get("position"), int) else 0)
    children = {}
    for component in components:
        if component.get("group") is not True and isinstance(component.get("group_id"), str):
            children.setdefault(component["group_id"], []).append(
                row(name_text(component["name"]), component.get("status")))
    rows = []
    for component in components:
        if component.get("group") is True:
            rows.append(row(name_text(component["name"]), component.get("status"),
                            children.get(component["id"], [])[:MAXIMUM_COMPONENTS]))
        elif component.get("group_id") is None:
            rows.append(row(name_text(component["name"]), component.get("status")))
    return rows


def parse_incidentio(payload):
    summary = payload["summary"]
    statuses = {a["component_id"]: a.get("status") for a in summary.get("affected_components") or []
                if isinstance(a, dict) and isinstance(a.get("component_id"), str)}

    def leaf(component):
        return row(name_text(component.get("name")), statuses.get(component.get("component_id"), "operational"))

    def visible(value):
        return isinstance(value, dict) and value.get("hidden") is not True and name_text(value.get("name"))

    rows = []
    for item in summary["structure"]["items"]:
        group, component = item.get("group"), item.get("component")
        if visible(group):
            leaves = [leaf(c) for c in group.get("components") or [] if visible(c)][:MAXIMUM_COMPONENTS]
            rows.append({"name": name_text(group["name"]), "indicator": worst(leaves), "children": leaves})
        elif visible(component):
            rows.append(leaf(component))
    return rows


def parse(kind, raw):
    rows = (parse_incidentio if kind == "incidentio" else parse_statuspage)(json.loads(raw))
    if not rows:
        raise ValueError("empty")
    return rows[:MAXIMUM_COMPONENTS]


def fetch(url):
    request = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "codexbar-plasma"})
    with urllib.request.build_opener(NoRedirect).open(request, timeout=10) as response:
        raw = response.read(MAXIMUM_BYTES + 1)
    if len(raw) > MAXIMUM_BYTES:
        raise ValueError("size")
    return raw


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--provider", required=True, choices=sorted(FEEDS))
    args = parser.parse_args()
    kind, url = FEEDS[args.provider]
    try:
        record = {"status": "ok", "components": parse(kind, fetch(url))}
    except Exception:  # noqa: BLE001 - every failure has the same bounded result
        record = {"status": "error"}
    print(json.dumps(record))


if __name__ == "__main__":
    main()
