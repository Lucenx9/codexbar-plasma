"""Exercise the applet's quota-cache adapters across an in-memory account selection."""

import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts/lib"))
from qml_surfaces import Surface

FUNCTIONS = (
    "copyObject", "providerMapKey", "accountKey", "accountOptionsForProvider",
    "usageCacheContext", "applyUsageTransition", "invalidateUsageData", "restoreUsageCache",
    "commitUsageSnapshot", "failUsageRefresh", "selectAccount", "replaceProviderSnapshot",
    "providerErrorPayload",
)

QML = '''import QtQuick
import QtTest
import "SOURCE_URL/Guards.js" as Guards
import "SOURCE_URL/ProviderNormalizer.js" as Normalizer
import "SOURCE_URL/ProviderOrder.js" as ProviderOrder
import "SOURCE_URL/ProviderSnapshot.js" as ProviderSnapshot
import "SOURCE_URL/UsageCache.js" as UsageCache
import "SOURCE_URL/UsageState.js" as UsageState
TestCase {
    name: "UsageCacheAccountSelection"
    // Plasma configuration survives a restart; selectedAccounts does not.
    QtObject {
        id: hostConfiguration
        property string usageCache: ""
    }
    Component {
        id: harness
        QtObject {
            id: root
            property string commandPath: "codexbar"
            property string provider: ""
            property string source: ""
            property int providerConfigRevision: 0
            property string commandSource: "codexbar usage"
            property string providerConfigStamp: "stamp"
            property string providerOrderRaw: ""
            property bool usageLifecycleInitialized: true
            property var providers: []
            property var selectedAccounts: ({})
            property var accountOptions: ({})
            property string lastUpdatedText: ""
            property double panelClockMs: 0
            property QtObject usageController: QtObject { function reset() {} }
            property QtObject accountsController: QtObject { function reset() {} }
            property QtObject timeLabels: QtObject { function clockTime(ms) { return String(ms) } }
            USAGE_IDENTITY_BINDING
            function i18n(text, first) { return text.replace("%1", first === undefined ? "%1" : first) }
            function normalizeProvider(item) { return ProviderSnapshot.normalize(item, Date.now()) }
            function markNotificationProvidersFresh(items) {}
            function markUsageSnapshotReceived(nowMs) {}
            function setNotificationProviderRefreshPending(key, value) {}
            function scheduleUsageRefresh() {}
            function providerTokenCost(providerID) { return null }
            SOURCE_FUNCTIONS
        }
    }

    function snapshot(provider, used, account) {
        var item = { provider: provider, usage: { updatedAt: new Date().toISOString(),
            primary: { usedPercent: used } } }
        if (account)
            item.account = account
        return ProviderSnapshot.normalize(item, Date.now())
    }

    function quotas(applet) {
        return applet.providers.map(function(item) {
            return item.provider + ":" + (UsageCache.hasQuota(item) ? item.rows[0].usedPercent : "-")
        }).join(",")
    }

    function restart(selection, live) {
        var applet = createTemporaryObject(harness, this, { selectedAccounts: selection || ({}) })
        if (live)
            applet.providers = live
        applet.restoreUsageCache()
        return applet
    }

    function launchWithDefaults() {
        hostConfiguration.usageCache = ""
        var applet = createTemporaryObject(harness, this)
        applet.commitUsageSnapshot([snapshot("codex", 40), snapshot("claude", 10)])
        compare(quotas(restart()), "codex:40,claude:10")
        return applet
    }

    function test_selectedAccountRefreshKeepsSiblingsAndNeverRestoresAsDefault() {
        var applet = launchWithDefaults()
        applet.selectAccount("codex", "work@example.test")
        compare(quotas(restart()), "claude:10")
        applet.commitUsageSnapshot([snapshot("codex", 80, "work@example.test"), snapshot("claude", 12)])
        compare(quotas(applet), "codex:80,claude:12")
        compare(quotas(restart()), "claude:12")
        verify(hostConfiguration.usageCache.indexOf("work@example.test") < 0)
        applet.failUsageRefresh("offline")
        compare(quotas(restart()), "claude:12")
    }

    function test_failedRefreshUnderSelectionKeepsSiblings() {
        var applet = launchWithDefaults()
        applet.selectAccount("codex", "work@example.test")
        applet.failUsageRefresh("offline")
        compare(quotas(restart()), "claude:10")
    }

    function test_returningToDefaultPersistsTheProviderAgain() {
        var applet = launchWithDefaults()
        applet.selectAccount("codex", "work@example.test")
        applet.commitUsageSnapshot([snapshot("codex", 80, "work@example.test"), snapshot("claude", 12)])
        applet.selectAccount("codex", "")
        compare(quotas(restart()), "claude:12")
        applet.commitUsageSnapshot([snapshot("codex", 45), snapshot("claude", 13)])
        compare(quotas(restart()), "codex:45,claude:13")
    }

    function test_lateRestoreNeverLeaksDefaultQuotaIntoSelectedAccount() {
        launchWithDefaults()
        var failure = ProviderSnapshot.normalize({ provider: "codex",
            error: { code: 1, kind: "provider", message: "offline" } }, Date.now())
        var applet = restart({ codex: "work@example.test" }, [failure])
        compare(quotas(applet), "codex:-,claude:10")
        verify(applet.providers[1].usageStale)
        // Without live results the overridden provider is not restored at all.
        compare(quotas(restart({ codex: "work@example.test" })), "claude:10")
        // The late restore republishes without the override's default quota.
        compare(quotas(restart()), "claude:10")
    }
}
'''


class UsageCacheAccountSelectionTests(unittest.TestCase):
    def test_root_cache_adapters_survive_account_selection_restart(self):
        surface = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        source = surface.texts[main]
        surface.texts = {main: source}
        functions = []
        for name in FUNCTIONS:
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + surface.function_body(name) + "}")
        binding = re.search(r"^ *readonly property string usageIdentityContext:[^\n]*\n[^\n]*$",
                            source, re.M).group(0)
        qml = QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("USAGE_IDENTITY_BINDING", binding.strip())
        qml = qml.replace("SOURCE_FUNCTIONS", "\n".join(functions))
        qml = qml.replace("Plasmoid.configuration", "hostConfiguration")
        with tempfile.TemporaryDirectory(prefix="codexbar-cache-selection-") as temporary:
            fixture = Path(temporary) / "tst_usage_cache_account_selection.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
