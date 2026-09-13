"""Exercise the owning cost/credit adapters against every compiled catalog."""

import gettext
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "scripts/lib"))
from compile_translations import compile_catalogs
from qml_surfaces import Surface


class ProviderCostPresentationTests(unittest.TestCase):
    def test_cost_and_reset_adapters_preserve_translated_sections(self):
        applet = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        applet.texts = {main: main.read_text()}
        applet.files = [main]
        signatures = {"providerCostSection": "providerID, cost",
                      "resetCreditsSection": "providerID, resetCredits",
                      "localizedPeriod": "value", "amountString": "value, currency"}
        adapters = "\n".join(f"function {name}({args}) {{ {applet.function_body(name)} }}"
                             for name, args in signatures.items())
        with tempfile.TemporaryDirectory(prefix="codexbar-cost-labels-") as temporary:
            directory = Path(temporary)
            compile_catalogs(directory / "locale")
            cases = []
            for language in ("en", "it", "fr", "de", "es", "pt_BR"):
                catalog = gettext.translation("plasma_applet_app.codexbar.plasma", directory / "locale",
                                              languages=[language], fallback=language == "en")
                messages = {key: value for key, value in getattr(catalog, "_catalog", {}).items()
                            if isinstance(key, str)}

                def text(source, *values):
                    result = catalog.gettext(source)
                    for index, value in enumerate(values, 1):
                        result = result.replace("%" + str(index), str(value))
                    return result

                def section(title, percent, spend, percent_line="", personal=""):
                    return {"title": text(title), "percentUsed": percent, "spendLine": spend,
                            "percentLine": percent_line, "personalSpendLine": personal}

                rows = [
                    {"provider": "claude", "cost": {"used": 25, "limit": 100, "personalUsed": 12},
                     "expected": section("Extra usage", 25,
                                         text("%1: %2 / %3", text("This month"), "$25.00", "$100.00"),
                                         text("%1% used", 25), text("Your spend: %1", "$12.00"))},
                    {"provider": "factory", "cost": {"used": 12.5, "limit": 100, "currencyCode": "EUR",
                                                        "period": "Extra usage balance"},
                     "expected": section("Extra usage", -1, text("Balance: %1", "EUR 12.50"))},
                    {"provider": "opencodego", "cost": {"used": 12.5, "limit": 100, "period": "Zen balance"},
                     "expected": section("Zen balance", -1, text("Balance: %1", "$12.50"))},
                    {"provider": "minimax", "cost": {"used": 12.5, "limit": 100, "period": "MiniMax points balance"},
                     "expected": section("Credits", -1, text("Balance: %1", 13))},
                    {"provider": "openai", "cost": {"used": 0, "period": "Billing cycle"},
                     "expected": section("API spend", -1, text("%1: %2", "Billing cycle", "$0.00"))},
                    {"provider": "future-provider", "cost": {"used": 10, "limit": 20, "currencyCode": "Quota",
                                                                "period": "Today"},
                     "expected": section("Quota usage", 50, text("%1: %2 / %3", text("Today"), 10, 20),
                                         text("%1% used", 50))},
                    {"provider": "future-provider", "cost": {"used": 2, "currencyCode": "Quota"},
                     "expected": section("Extra usage", -1, text("%1: %2", text("This month"), 2))},
                    {"provider": "claude", "cost": {"used": -1, "limit": 10, "personalUsed": 0,
                                                       "period": "last 30 days"},
                     "expected": section("Extra usage", 0,
                                         text("%1: %2 / %3", text("Last 30 days"), "-$1.00", "$10.00"),
                                         text("%1% used", 0))},
                    {"provider": "litellm", "cost": {"used": 10, "limit": 0}, "expected": None},
                    {"provider": "manus", "cost": {"used": 10, "limit": 100}, "expected": None},
                    {"provider": "codex", "cost": {"used": False, "limit": 100}, "expected": None},
                ]
                plural_messages = {count: catalog.ngettext("%1 available", "%1 available", count)
                                   for count in (0, 1, 2)}
                counts = [{"input": count, "expected": {"title": text("Reset credits"),
                            "line": plural_messages[rounded].replace("%1", str(rounded))}}
                          for count, rounded in ((1, 1), ("2", 2), (1.6, 2), (0.2, 0))]
                cases.append({"tag": language, "messages": messages, "plurals": plural_messages,
                              "rows": rows, "counts": counts})
            qml = '''import QtQuick
import QtTest
import "SOURCE_URL/ProviderCostPresentation.js" as ProviderCostPresentation
import "SOURCE_URL/CostPresentation.js" as CostPresentation
TestCase {
    name: "ProviderCostAdapters"
    property var messages: ({})
    property var plurals: ({})
    property var costNumberFormat: CostPresentation.numberFormat(",", ".")
    function i18n(source) {
        var text = messages[source] || source;
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, String(arguments[i]));
        return text;
    }
    function i18np(one, many, count) {
        return plurals[count].replace("%1", String(count));
    }
    ADAPTERS
    function test_sections_data() { return CASES; }
    function test_sections(data) {
        messages = data.messages;
        plurals = data.plurals;
        for (var row of data.rows)
            compare(providerCostSection(row.provider, row.cost), row.expected, row.provider);
        for (var count of data.counts)
            compare(resetCreditsSection("codex", {availableCount: count.input}), count.expected);
        compare(resetCreditsSection("claude", {availableCount: 2}), null);
        compare(resetCreditsSection("codex", {availableCount: 0}), null);
    }
}
'''
            fixture = directory / "tst_provider_cost_adapters.qml"
            fixture.write_text(qml.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
                               .replace("ADAPTERS", adapters).replace("CASES", json.dumps(cases)))
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("SKIP", output)
            self.assertNotIn("QWARN", output)


if __name__ == "__main__":
    unittest.main()
