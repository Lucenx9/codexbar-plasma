#!/usr/bin/env python3
"""Capture the real compact applet across content combinations using OpenGL."""

import argparse
import configparser
import hashlib
import html
import io
import itertools
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

import smoke_popup as smoke

DEFAULTS = {
    "panelStyle": "standard", "showProviderInPanel": False,
    "showPercentInPanel": False, "showCreditsInPanel": False,
    "showMultiProviderInPanel": True, "panelQuotaLane": "auto",
    "panelElementOrder": "identity,status,text,meters", "panelVisibilityRules": "{}",
    "menuBarDisplayMode": "percent", "autoSelectProvider": False,
    "usageBarsShowUsed": True, "resetTimesShowAbsolute": False,
}
CONTENTS = ("showProviderInPanel", "showPercentInPanel", "showCreditsInPanel", "showMultiProviderInPanel")


def matrix_cases(vertical=False):
    cases = []

    def add(name, config=None, **options):
        cases.append({"id": name, "config": DEFAULTS | (config or {}),
                      "extent": 32, "vertical": vertical, **options})

    for style in ("standard", "minimal"):
        for flags in itertools.product((False, True), repeat=4):
            add(style + "-" + "".join(str(int(flag)) for flag in flags),
                dict(zip(CONTENTS, flags)) | {"panelStyle": style})
    if vertical:
        return cases
    all_text = {key: True for key in CONTENTS}
    for order in itertools.permutations(("identity", "status", "text", "meters")):
        add("order-" + "-".join(order), all_text | {"panelElementOrder": ",".join(order)})
    for style in ("standard", "minimal"):
        for mode in ("percent", "pace", "both", "runOut", "resetTime"):
            add(style + "-mode-" + mode, all_text | {"panelStyle": style, "menuBarDisplayMode": mode})
        for extent in (24, 48, 64):
            add(style + "-height-" + str(extent), all_text | {"panelStyle": style}, extent=extent)
        add(style + "-long-name", all_text | {"panelStyle": style}, longName=True)
    for lane in ("primary", "secondary", "tertiary"):
        add("quota-" + lane, all_text | {"panelQuotaLane": lane})
    for edge in ("missing-secondary", "no-quotas", "exhausted"):
        add(edge, all_text, edge=edge)
    add("remaining", all_text | {"usageBarsShowUsed": False}, edge="exhausted")
    for target in ("text", "meters"):
        add("hidden-" + target, all_text | {"panelVisibilityRules": json.dumps({
            target: {"condition": "usageAtLeast", "usedPercent": 100}})})
    add("credits-unavailable", {"showCreditsInPanel": True}, selected="claude")
    add("order-text-only", {"showPercentInPanel": True,
        "panelElementOrder": "identity,text,status,meters"}, selected="claude")
    return cases


def apply_palette(work, theme):
    palette = configparser.ConfigParser()
    palette.optionxform = str
    name = "BreezeDark" if theme == "dark" else "BreezeLight"
    if not palette.read("/usr/share/color-schemes/" + name + ".colors"):
        raise RuntimeError("Missing " + name + " color scheme")
    for section in list(palette.sections()):
        if not section.startswith(("Colors:", "ColorEffects:")):
            palette.remove_section(section)
    colors = io.StringIO()
    palette.write(colors)
    with (work / "config/kdeglobals").open("a") as config:
        config.write("\n" + colors.getvalue())


def validate_record(record, count):
    """Check visible geometry and the independent, fixed base-fixture contract."""
    if record["width"] <= 0 or record["height"] <= 0:
        raise RuntimeError("Empty panel: " + record["id"])
    for part in record["parts"]:
        if (part["width"] <= 0 or part["height"] <= 0 or part["x"] < -1 or part["y"] < -1
                or part["x"] + part["width"] > record["width"] + 1
                or part["y"] + part["height"] > record["height"] + 1):
            raise RuntimeError("Clipped panel element: " + record["id"] + ": " + part["name"])
    flags = re.fullmatch(r"(?:standard|minimal)-([01]{4})", record["id"])
    if not flags:
        return
    name, usage, credits, meters = (flag == "1" for flag in flags[1])
    expected = " ".join(value for value, enabled in
                        (("Codex", name), ("43% used", usage), ("125cr", credits)) if enabled)
    if record["text"] != expected:
        raise RuntimeError("Content mismatch: " + record["id"])
    tracks = [part for part in record["parts"] if part["name"] == "panelMeterTrack"]
    labels = [part for part in record["parts"] if part["name"] in ("panelProviderText", "panelStandaloneText")]
    if len(tracks) != (count * 2 if meters else 0):
        raise RuntimeError("Missing or unexpected quota capsule: " + record["id"])
    if len(labels) != (1 if expected and not record["case"]["vertical"] else 0):
        raise RuntimeError("Missing or duplicated panel text: " + record["id"])


def capture_batch(output, theme, count, vertical):
    name = f"{theme}-{count}-" + ("vertical" if vertical else "horizontal")
    batch = output / name
    batch.mkdir()
    cases = matrix_cases(vertical)
    if count == 1:
        cases = [case for case in cases if case.get("selected", "codex") == "codex"]
    scenario = "panel-matrix-one" if count == 1 else "panel-matrix-three"
    with tempfile.TemporaryDirectory(prefix="codexbar-matrix-") as temporary:
        work = Path(temporary)
        env = smoke.preview_environment(work, scenario, "opengl")
        smoke.stage_applet(work, scenario, batch)
        apply_palette(work, theme)
        ui = work / "data/plasma/plasmoids" / smoke.APPLET_ID / "contents/ui"
        shutil.copyfile(smoke.ROOT / "scripts/smoke/PanelMatrixCapture.qml", ui / "SmokeCapture.qml")
        main = (ui / "main.qml").read_text()
        main = main.replace("cacheRestart: false", "expectedProviders: " + str(count)
                            + "\n        cases: " + json.dumps(cases))
        if vertical:
            expression = "Plasmoid.formFactor === PlasmaCore.Types.Vertical"
            if expression not in main:
                raise RuntimeError("Missing vertical panel adapter")
            main = main.replace(expression, "true")
        (ui / "main.qml").write_text(main)
        command = [shutil.which("dbus-run-session"), "--", shutil.which("plasmawindowed"), smoke.APPLET_ID]
        smoke.run_preview(command, env, work, batch / "capture.log", scenario, 90)
    records = [json.loads(line.split("PANEL_MATRIX_RESULT:", 1)[1])
               for line in (batch / "capture.log").read_text().splitlines()
               if "PANEL_MATRIX_RESULT:" in line]
    if [row["id"] for row in records] != [case["id"] for case in cases]:
        raise RuntimeError("Incomplete matrix batch: " + name)
    for record, case in zip(records, cases):
        image = batch / (record["id"] + ".png")
        if not image.is_file() or image.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
            raise RuntimeError("Missing matrix screenshot: " + str(image))
        record.update(case=case, batch=name, image=str(image.relative_to(output)))
        validate_record(record, count)
    return records


def write_report(output, records):
    (output / "results.json").write_text(json.dumps(records, indent=2) + "\n")
    cards = []
    for record in records:
        enabled = [name for name, key in zip(("Name", "Usage", "Credits", "Meters"), CONTENTS)
                   if record["case"]["config"][key]]
        cards.append('<article data-batch="' + record["batch"] + '"><h2>' + html.escape(record["id"])
                     + '</h2><p>' + (" · ".join(enabled) or "Icon only") + '</p><img src="'
                     + html.escape(record["image"], quote=True) + '" alt="Panel capture"><p>'
                     + html.escape(record["text"]) + '</p></article>')
    (output / "index.html").write_text('''<!doctype html><meta charset="utf-8">
<title>CodexBar panel matrix</title><style>
body{font:14px system-ui;margin:24px;background:#eee;color:#222}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(450px,1fr));gap:16px}
article{background:white;padding:12px;border:1px solid #bbb}h2{font-size:14px}p{margin:8px 0}img{display:block;max-width:100%;height:auto}
</style><h1>Panel configuration matrix</h1><p>Real Plasma rendering, OpenGL, synthetic data. Images at native size. Automated capture is not a visual approval.</p>
<label>Batch <select id="batch"></select></label>
<label><input id="base" type="checkbox">Base content combinations only</label><main>'''
        + "\n".join(cards) + '''</main><script>
const cards=[...document.querySelectorAll('article')], batch=document.querySelector('#batch'), base=document.querySelector('#base');
for(const name of new Set(cards.map(card=>card.dataset.batch))) batch.add(new Option(name,name));
function filter(){ for(const card of cards) card.hidden=card.dataset.batch!==batch.value || (base.checked && !/^(standard|minimal)-[01]{4}$/.test(card.querySelector('h2').textContent)); }
batch.addEventListener('change',filter); base.addEventListener('change',filter); filter();
</script>\n''')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path, help="New artifact directory")
    parser.add_argument("--vertical", action="store_true", help="Also capture all content combinations on vertical panels")
    args = parser.parse_args()
    if not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY"):
        parser.error("A graphical session is required; use xvfb-run in CI")
    for tool in ("plasmawindowed", "dbus-run-session"):
        if not shutil.which(tool):
            parser.error("Required command not found: " + tool)
    output = args.output.resolve()
    if output.exists():
        parser.error("--output must name a new directory")
    output.mkdir(parents=True)
    digest = hashlib.sha256()
    for source in sorted((smoke.ROOT / "contents").rglob("*")):
        if source.is_file():
            digest.update(str(source.relative_to(smoke.ROOT)).encode() + b"\0" + source.read_bytes())
    metadata = {"contents_sha256": digest.hexdigest(), "renderer": "opengl", "vertical": args.vertical}
    try:
        metadata["commit"] = subprocess.check_output(["git", "rev-parse", "HEAD"],
            cwd=smoke.ROOT, text=True, stderr=subprocess.DEVNULL).strip()
        metadata["changes"] = subprocess.check_output(["git", "status", "--short"],
            cwd=smoke.ROOT, text=True, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.CalledProcessError):
        metadata["commit"] = None  # Archives and mounted worktrees may have no Git metadata.
    (output / "source.json").write_text(json.dumps(metadata, indent=2) + "\n")
    records = []
    for vertical in ((False, True) if args.vertical else (False,)):
        for theme, count in itertools.product(("light", "dark"), (1, 3)):
            records.extend(capture_batch(output, theme, count, vertical))
            write_report(output, records)
            print(f"Captured {len(records)} cases: {output / 'index.html'}", flush=True)


if __name__ == "__main__":
    main()
