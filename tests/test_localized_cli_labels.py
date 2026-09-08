"""Run the owning QML label adapters against compiled catalogs without Plasma."""

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


class LocalizedCliLabelTests(unittest.TestCase):
    def test_session_and_pace_adapters_use_each_catalog(self):
        applet = Surface("applet", ROOT)
        signatures = {"sessionStateText": "state", "sessionSourceText": "source",
                      "sessionSubtitle": "item", "capitalize": "value",
                      "paceSummaryText": "pace", "paceEtaText": "seconds"}
        adapters = "\n".join(f"function {name}({args}) {{ {applet.function_body(name)} }}"
                             for name, args in signatures.items())
        expected = {
            "it": ["Attiva", "Inattiva", "In esecuzione", "Al lavoro", "Applicazione desktop",
                   "Riga di comando", "13% oltre il previsto | Utilizzo previsto: 30% | Esaurimento previsto tra 1 ora"],
            "fr": ["Active", "Inactive", "En cours", "Au travail", "Application de bureau",
                   "Ligne de commande", "13% au-delà du prévu | Utilisation prévue : 30% | Épuisement prévu dans 1 heure"],
            "de": ["Aktiv", "Inaktiv", "Wird ausgeführt", "In Bearbeitung", "Desktop-Anwendung",
                   "Befehlszeile", "13% über dem Soll | Erwarteter Verbrauch: 30% | Voraussichtlich in 1 Stunde aufgebraucht"],
            "es": ["Activa", "Inactiva", "En ejecución", "Trabajando", "Aplicación de escritorio",
                   "Línea de comandos", "13% por encima de lo previsto | Uso previsto: 30% | Agotamiento previsto en 1 hora"],
            "pt_BR": ["Ativa", "Inativa", "Em execução", "Trabalhando", "Aplicativo de desktop",
                      "Linha de comando", "13% acima do previsto | Uso previsto: 30% | Esgotamento previsto em 1 hora"],
        }
        with tempfile.TemporaryDirectory(prefix="codexbar-localized-labels-") as temporary:
            directory = Path(temporary)
            compile_catalogs(directory / "locale")
            cases = []
            for language, labels in expected.items():
                catalog = gettext.translation("plasma_applet_app.codexbar.plasma", directory / "locale",
                                              languages=[language])
                messages = {key: value for key, value in catalog._catalog.items() if isinstance(key, str)}
                messages["%1 hour"] = catalog.ngettext("%1 hour", "%1 hours", 1)
                cases.append({"tag": language, "messages": messages, "labels": labels})
            # The real Plasma/KI18n domain lookup is covered by the graphical
            # smoke scenario. Here only that lookup is replaced with GNU gettext.
            qml = '''import QtQuick
import QtTest
import PACE_PATH as PacePresentation
import PRIVACY_PATH as PrivacyPresentation
TestCase {
    name: "LocalizedCliLabels"
    property var messages: ({})
    property bool privacyMode: false
    function i18n(source) {
        var text = messages[source] || source;
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, String(arguments[i]));
        return text;
    }
    function i18np(one, many, count) { return i18n(count === 1 ? one : many, count); }
    ADAPTERS
    function test_labels_data() { return CASES; }
    function test_labels(row) {
        privacyMode = false;
        messages = row.messages;
        var states = ["active", "idle", "running", "working"];
        for (var i = 0; i < states.length; i++)
            compare(sessionStateText(states[i]), row.labels[i]);
        compare(sessionStateText(""), i18n("Unknown"));
        compare(sessionStateText("unknown"), i18n("Unknown"));
        compare(sessionStateText("futureState"), "FutureState");
        compare(sessionSourceText("desktopApp"), row.labels[4]);
        compare(sessionSourceText("cli"), row.labels[5]);
        compare(sessionSourceText("ide"), "IDE");
        compare(sessionSourceText("unknown"), i18n("Unknown"));
        compare(sessionSourceText("futureSource"), "futureSource");
        compare(sessionSubtitle({provider: "", host: "workstation", source: "desktopApp"}),
            "workstation - " + row.labels[4]);
        compare(paceSummaryText({stage: "ahead", deltaPercent: 13, expectedUsedPercent: 30,
            willLastToReset: false, etaSeconds: 3600, summary: "English summary"}), row.labels[6]);
        compare(paceSummaryText({stage: "onTrack", willLastToReset: true}),
            i18n("On pace") + " | " + i18n("Lasts until reset"));
        compare(paceSummaryText({stage: "behind", deltaPercent: -3}), i18n("%1% in reserve", 3));
        compare(paceSummaryText({willLastToReset: false, etaSeconds: 0}), i18n("Runs out now"));
        compare(paceSummaryText({summary: "Legacy forecast"}), "Legacy forecast");
        compare(paceSummaryText(null), "");
        privacyMode = true;
        compare(sessionStateText("futureState"), i18n("Unknown"));
        compare(sessionSourceText("futureSource"), i18n("Unknown"));
        compare(sessionSubtitle({provider: "", host: "workstation", source: "desktopApp"}), row.labels[4]);
    }
}
'''
            fixture = directory / "tst_labels.qml"
            fixture.write_text(qml.replace("PACE_PATH", json.dumps((ROOT / "contents/ui/PacePresentation.js").as_uri()))
                               .replace("PRIVACY_PATH", json.dumps((ROOT / "contents/ui/PrivacyPresentation.js").as_uri()))
                               .replace("ADAPTERS", adapters).replace("CASES", json.dumps(cases)), encoding="utf-8")
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
