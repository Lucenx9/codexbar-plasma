"""Targeted synthetic panel ring cases and their capture assertions."""


def add_ring_cases(add, content_keys):
    for style in ("standard", "minimal"):
        ring_config = {"panelStyle": style, "panelMeterShape": "rings"}
        add("rings-" + style, ring_config)
        for extent in (24, 48, 64):
            add("rings-" + style + "-height-" + str(extent), ring_config, extent=extent)
        for edge in ("tiny", "warning", "stale-confidence-incident", "missing-secondary", "no-quotas", "exhausted"):
            add("rings-" + style + "-" + edge, ring_config, edge=edge)
        add("rings-" + style + "-stale-confidence-incident-24", ring_config,
            edge="stale-confidence-incident", extent=24)
        for interaction in ("hover", "press", "focus"):
            add("rings-" + style + "-" + interaction, ring_config, interaction=interaction)
        for lane in ("primary", "secondary"):
            add("rings-" + style + "-" + lane, ring_config | {"panelQuotaLane": lane})
        add("rings-" + style + "-remaining", ring_config | {"usageBarsShowUsed": False}, edge="exhausted")
        add("rings-" + style + "-text", ring_config | {key: True for key in content_keys})


def validate_ring_record(record, count):
    if record["case"].get("config", {}).get("panelMeterShape") != "rings":
        return
    rings = [part for part in record["parts"] if part["name"] == "panelMeterRing"]
    expected_rings = count * (1 if record["case"]["config"]["panelQuotaLane"] != "auto" else 2)
    expected_rings -= {"missing-secondary": 1, "no-quotas": 2}.get(record["case"].get("edge"), 0)
    if len(rings) != expected_rings:
        raise RuntimeError("Missing or duplicated quota ring: " + record["id"])
    if any(part["name"] == "panelMeterTrack" for part in record["parts"]):
        raise RuntimeError("Capsules remain visible with rings: " + record["id"])
