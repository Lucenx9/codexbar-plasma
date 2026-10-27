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
# StatusComponents.js rejects longer stdout; print() adds one newline.
MAXIMUM_OUTPUT = 262144
# Matches the upstream CodexBar mapping to the CLI's status indicator values.
INDICATORS = {
    "operational": "none",
    "degraded_performance": "minor",
    "partial_outage": "major",
    "major_outage": "critical",
    "full_outage": "critical",
    "under_maintenance": "maintenance",
}
# Upstream ranks unknown with maintenance when a group takes its worst child.
RANK = {"none": 0, "maintenance": 1, "unknown": 1, "minor": 2, "major": 3, "critical": 4}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def name_text(value):
    if not isinstance(value, str):
        return ""
    return re.sub(r"[\x00-\x1f\x7f]+", " ", value).strip()[:MAXIMUM_NAME].strip()


def row(name, status, children=()):
    indicator = INDICATORS.get(status, "unknown") if isinstance(status, str) else "unknown"
    return {"name": name, "indicator": indicator, "children": list(children)}


def worst(children):
    return max((child["indicator"] for child in children), key=RANK.get, default="none")


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
    # As upstream, an affected entry without a status leaves the component operational.
    statuses = {a["component_id"]: a["status"] for a in summary.get("affected_components") or []
                if isinstance(a, dict) and isinstance(a.get("component_id"), str) and isinstance(a.get("status"), str)}

    def leaf(component):
        component_id = component.get("component_id")
        state = statuses.get(component_id, "operational") if isinstance(component_id, str) and component_id else None
        return row(name_text(component.get("name")), state)

    def visible(value):
        return isinstance(value, dict) and value.get("hidden") is not True and name_text(value.get("name"))

    rows = []
    for item in summary["structure"]["items"]:
        if not isinstance(item, dict):
            continue
        group, component = item.get("group"), item.get("component")
        if visible(group):
            leaves = [leaf(c) for c in group.get("components") or [] if visible(c)]
            rows.append({"name": name_text(group["name"]), "indicator": worst(leaves),
                         "children": leaves[:MAXIMUM_COMPONENTS]})
        elif visible(component):
            rows.append(leaf(component))
    return rows


def within_output(rows):
    """Keep leading rows and children whose printed record fits the reader's limit.

    Default json.dumps output composes: each list item adds its own length plus
    a ", " separator, so the budget is exact. Group indicators were computed
    before trimming, so a dropped child never lowers its group's severity.
    """
    budget = MAXIMUM_OUTPUT - 1 - len(json.dumps({"status": "ok", "components": []}))
    kept = []
    for value in rows:
        group = {**value, "children": []}
        cost = len(json.dumps(group)) + (2 if kept else 0)
        if cost > budget:
            break
        budget -= cost
        for child in value["children"]:
            cost = len(json.dumps(child)) + (2 if group["children"] else 0)
            if cost > budget:
                break
            budget -= cost
            group["children"].append(child)
        kept.append(group)
    return kept


def parse(kind, raw):
    rows = (parse_incidentio if kind == "incidentio" else parse_statuspage)(json.loads(raw))
    if not rows:
        raise ValueError("empty")
    return within_output(rows[:MAXIMUM_COMPONENTS])


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
