"""Static checks for provider identity, usage, account, and snapshot data flow in
the applet."""

import re
import unittest

from ui_regression_support import (
    Surface,
    code_contains,
    function_body,
    id_block,
    provider_accounts_panel_qml,
    providers_qml,
    root,
)

# The popup UI rules below belong to the plasmoid surface, not to main.qml
# specifically, so read the surface as one text. Extracting the popup into a
# component keeps these assertions meaningful instead of silently unhooking them.
applet = Surface("applet", root)
main_text = applet.text
popup_surface = Surface("popup", root)
providers_text = providers_qml.read_text(encoding="utf-8")
provider_accounts_panel_text = provider_accounts_panel_qml.read_text(encoding="utf-8")


class ProviderDataTest(unittest.TestCase):
    def test_provider_identity_is_shared(self):
        # Provider identity used to be two copies, and this file carried a drift check
        # that compared them entry by entry. The tables now live once in
        # ProviderIdentity.js, so what is worth asserting is that neither surface has
        # grown a private copy again: both must read the shared module.
        for source_text, label in ((main_text, "main.qml"), (providers_text, "configProviders.qml")):
            for function_name, shared_call in (
                ("providerKey", "ProviderIdentity.resolveProviderKey(value)"),
                ("providerCliArgument", "ProviderIdentity.providerCliArgument(value)"),
                ("providerColor", "ProviderIdentity.providerBrandColorChannels(value)"),
                ("providerIconSource", "ProviderIdentity.providerIconFileName(value)"),
                ("providerDashboardUrl", "ProviderIdentity.providerDashboardUrl(providerID)"),
                ("providerDocsUrl", "ProviderIdentity.providerDocsUrl(providerID)"),
                ("providerLoginUrl", "ProviderIdentity.providerLoginUrl(providerID)"),
            ):
                body = function_body(source_text, function_name)
                if shared_call not in body:
                    raise AssertionError(
                        f"{label}: {function_name} must read provider identity from "
                        f"ProviderIdentity.js instead of a local table"
                    )
                if 'case "' in body or "var aliases = {" in body:
                    raise AssertionError(
                        f"{label}: {function_name} has grown a local provider table again"
                    )

        # The display names used to be two copies compared entry by entry. They now
        # live once in components/ProviderNames.qml, whose literal i18n() strings
        # gettext still scans; what is worth asserting is that neither surface has
        # grown a private copy again: both must read the shared component.
        for source_text, label in ((main_text, "main.qml"), (providers_text, "configProviders.qml")):
            title_body = function_body(source_text, "providerTitle")
            if not code_contains(title_body, "providerNames.titleForKey("):
                raise AssertionError(
                    f"{label}: providerTitle must read display names from "
                    "components/ProviderNames.qml"
                )
            if "var names = {" in title_body:
                raise AssertionError(
                    f"{label}: providerTitle has grown a local display-name table again"
                )

        # Wayfinder was added late and is the canary for a half-finished provider.
        identity_text = (root / "contents/ui/ProviderIdentity.js").read_text(encoding="utf-8")
        for identity_fragment, requirement in (
            ('"wayfinder": "wayfinder.md"', "documentation link"),
            ('"wayfinder": [', "brand color"),
        ):
            if not code_contains(identity_text, identity_fragment):
                raise AssertionError(f"ProviderIdentity.js must expose the Wayfinder {requirement}")
        names_text = (root / "contents/ui/components/ProviderNames.qml").read_text(encoding="utf-8")
        if '"wayfinder": i18n("Wayfinder")' not in function_body(names_text, "titleForKey"):
            raise AssertionError("ProviderNames.qml must expose the Wayfinder display name")

    def test_provider_config_parsing(self):
        provider_config_body = function_body(main_text, "normalizeProviderConfigEntries")
        if not code_contains(provider_config_body, "Array.isArray(payload) ? payload : [payload]"):
            raise AssertionError(
                "parseProviderConfigOutput must accept a single provider object as well "
                "as the normal provider-list array"
            )

        config_watch_body = function_body((root / "contents/ui/ProviderConfigWatch.js").read_text(), "watchCommand")
        for config_path_fragment in (
            "CODEXBAR_CONFIG",
            "XDG_CONFIG_HOME",
            "$HOME/.config/codexbar/config.json",
            "$HOME/.codexbar/config.json",
        ):
            if not code_contains(config_watch_body, config_path_fragment):
                raise AssertionError(
                    "ProviderConfigWatch.watchCommand must mirror the CLI config path resolver; "
                    f"missing {config_path_fragment!r}"
                )
        if config_watch_body.index("CODEXBAR_CONFIG") > config_watch_body.index("XDG_CONFIG_HOME"):
            raise AssertionError("CODEXBAR_CONFIG must take precedence over XDG_CONFIG_HOME")

    def test_usage_commands_and_roster_lifecycle(self):
        retire_body = function_body(main_text, "retireUsageCommands")
        for stale_account_fragment in (
            'retireUsageCommandKind("account")',
            "accountLoading = ({})",
        ):
            if stale_account_fragment in retire_body:
                raise AssertionError(
                    "retireUsageCommands must not drop in-flight account loads during "
                    f"refresh; found {stale_account_fragment!r}"
                )

        provider_roster_load_body = popup_surface.function_body("loadProviderRoster")
        if not code_contains(provider_roster_load_body, "disconnectProviderRosterCommands()"):
            raise AssertionError(
                "loadProviderRoster must invalidate older provider roster commands "
                "before connecting a replacement"
            )
        popup_surface.require(
            "function disconnectProviderRosterCommands()",
            "Popup must define provider roster command retirement",
        )

        provider_index_body = function_body(main_text, "providerIndexForID")
        if "return -1" not in provider_index_body or "return 0" in provider_index_body:
            raise AssertionError("providerIndexForID must return -1 instead of falling back to provider 0")
        if not code_contains(main_text, "var nextProviderIndex = applet.providerIndex(providerData)" not in main_text or "if (nextProviderIndex >= 0)"):
            raise AssertionError("Overview provider selection must ignore missing providers instead of selecting index 0")

        bounded_revision_body = function_body(main_text, "boundedConfigRevision")
        if "2147480000" not in bounded_revision_body or "1000000" in bounded_revision_body:
            raise AssertionError("boundedConfigRevision must use the same cap as bumpProviderConfigRevision")

    def test_usage_response_boundary(self):
        usage_controller_text = (root / "contents/ui/controllers/UsageController.qml").read_text()
        usage_response_text = (root / "contents/ui/UsageResponse.js").read_text()
        if "UsageResponse.response(" not in function_body(usage_controller_text, "parseOutput"):
            raise AssertionError("usage parsing must cross the bounded pure response interface")
        if not code_contains(usage_response_text, "Normalizer.dedupeProviderSnapshots(snapshots)"):
            raise AssertionError("direct usage payloads must not create duplicate provider tabs")

        refresh_body = function_body(usage_controller_text, "refreshNow")
        if "refreshCost(" in refresh_body or 'retireUsageCommandKind("cost")' in refresh_body:
            raise AssertionError("quota refreshes must not start or retire independent cost scans")
        fallback_body = function_body(usage_controller_text, "canUseProviderFallback")
        if not code_contains(fallback_body, "controller.sourceMode.length === 0 || hasSelectedAccountOverrides()"):
            raise AssertionError("account overrides must force provider-scoped refreshes")
        empty_command_index = refresh_body.find("if (commandSource.length === 0)")
        loading_false_index = refresh_body.find("failUsageRefresh(", empty_command_index)
        empty_return_index = refresh_body.find("return", empty_command_index)
        if empty_command_index < 0 or loading_false_index < 0 or loading_false_index > empty_return_index:
            raise AssertionError("refreshNow must clear loading before returning for an empty command")

        if "loading = false" not in function_body(usage_controller_text, "failUsageRefresh"):
            raise AssertionError("failed usage refreshes must finish loading")

    def test_quota_normalization(self):
        snapshot_text = (root / "contents/ui/ProviderSnapshot.js").read_text()
        window_body = function_body(snapshot_text, "windowSnapshot")
        for fragment in ("Normalizer.rateWindowMetrics(", "Guards.copyObject(metrics)",
                         "result.resetsAt = resetsAtText(",
                         "result.resetDescription = Normalizer.boundedDisplayText(",
                         "result.paceObservedAtMs = receivedAtMs"):
            if not code_contains(window_body, fragment):
                raise AssertionError("quota normalization must preserve reset and forecast data")
        # The stored reset is read back as a date string by the countdown, the panel
        # reset rule, and absolute formatting, so a numeric CLI date keeps its ISO form
        # and every other value stays bounded display text.
        resets_at_body = function_body(snapshot_text, "resetsAtText")
        for fragment in ("typeof value === \"number\"", "new Date(value).toISOString()",
                         "Normalizer.boundedDisplayText("):
            if not code_contains(resets_at_body, fragment):
                raise AssertionError(
                    "stored quota reset dates must stay parsable and bounded; "
                    f"missing {fragment!r}"
                )
        if "row.reset = Normalizer.boundedDisplayText(resetText(" not in function_body(main_text, "presentUsageWindow"):
            raise AssertionError("QML must format the initial reset label")
        if "onResetTimesShowAbsoluteChanged: Qt.callLater(refreshNow)" in main_text:
            raise AssertionError("changing reset formatting must not fan out new CLI requests")

        normalize_provider_body = function_body(snapshot_text, "normalize")
        if not code_contains(normalize_provider_body, "Normalizer.strictFiniteNumber(credits.remaining)"):
            raise AssertionError("remaining credits must reject coercive CLI numeric values")
        if not code_contains(normalize_provider_body, "Normalizer.normalizeCodexCreditLimit("):
            raise AssertionError("Codex monthly limits must cross the shared bounded normalizer")
        if not code_contains(normalize_provider_body, 'hasOwnKey(credits, "codexCreditLimit")'):
            raise AssertionError("Codex monthly limits must come from an own credits field")
        if not code_contains(normalize_provider_body, "credits: isFinite(remaining)"):
            raise AssertionError("the plain credits balance must remain independent of the monthly limit")
        if "credits: codexCreditLimit" in normalize_provider_body:
            raise AssertionError("the monthly-limit remainder must not replace the plain credits balance")
        direct_number_call = re.compile(r"(?<![A-Za-z0-9_])Number\(")
        if direct_number_call.search(normalize_provider_body):
            raise AssertionError("remaining credits must not use loose numeric coercion")

    def test_account_selection_and_cache_restore(self):
        if not code_contains(provider_accounts_panel_text, "accountIsSelected(modelData, accountsPanel.providerData)"):
            raise AssertionError("restored account bindings must follow the selected account state")

        clear_account_override_button = id_block(
            provider_accounts_panel_text, "clearAccountOverrideButton")
        for clear_override_fragment in (
            "visible: accountsPanel.applet.selectedAccountForProvider(accountsPanel.providerID).length > 0",
            'accountsPanel.applet.selectAccount(accountsPanel.providerID, "")',
            'Accessible.name: i18n("Use default account")',
        ):
            if clear_override_fragment not in clear_account_override_button:
                raise AssertionError(
                    "an account override must remain removable after its account disappears; "
                    f"missing {clear_override_fragment!r}"
                )
        if not code_contains(provider_accounts_panel_text, "|| applet.selectedAccountForProvider(providerID).length > 0"):
            raise AssertionError("an orphaned account override must keep its removal control visible")

        select_account_body = function_body(main_text, "selectAccount")
        pending_index = select_account_body.find("setNotificationProviderRefreshPending(key, true)")
        snapshot_index = select_account_body.find("replaceProviderSnapshot(key, options[i])")
        refresh_index = select_account_body.find("scheduleUsageRefresh()", snapshot_index)
        return_index = select_account_body.find("return", snapshot_index)
        if pending_index < 0 or snapshot_index < 0 or pending_index > snapshot_index:
            raise AssertionError("selectAccount must suppress cached snapshots until fresh usage data arrives")
        if refresh_index < 0 or return_index < 0 or refresh_index > return_index:
            raise AssertionError("selectAccount must schedule a fresh usage request before returning a cached snapshot")
        if "Qt.callLater(refreshNow)" in select_account_body:
            raise AssertionError(
                "selectAccount must schedule refreshes through scheduleUsageRefresh; a direct callLater(refreshNow) "
                "double-starts the usage command when the selectedAccounts write already changed commandSource"
            )
        usage_wiring = id_block(main_text, "usageController")
        for fragment in ("onSnapshotReceived:", "root.commitUsageSnapshot(", "root.presentProviderSnapshot(item)",
                         "onFailed:", "root.failUsageRefresh(message)", "onEmptyRoster: root.invalidateUsageData()"):
            if fragment not in usage_wiring:
                raise AssertionError("usage results must reach the applet cache boundary: " + fragment)
        restore_body = function_body(main_text, "restoreUsageCache")
        restore_steps = [restore_body.find(fragment) for fragment in (
            "UsageCache.decode(", "root.normalizeProvider(payload)", "item.tokenCost = null",
            "UsageCache.restore(cachedProviders, providers, nowMs, selectedAccounts)",
            "providers = ProviderOrder.orderedItems(merged, providerOrderRaw)",
        )]
        if min(restore_steps) < 0 or restore_steps != sorted(restore_steps):
            raise AssertionError("startup cache restore must merge normalized, redacted quotas with early live results")
        if "providers.every(" in restore_body:
            raise AssertionError("a successful partial startup refresh must not bypass cached-provider restoration")
        if "UsageCache.reconcile(providers, items, nowMs)" not in function_body(main_text, "commitUsageSnapshot"):
            raise AssertionError(
                "the live refresh must reconcile without an account pin; only the fingerprinted cache restore may skip "
                "the account-key comparison for a provider whose explicit selection it verified"
            )
        panel_clock_body = id_block(main_text, "panelClockTimer")
        for fragment in ("root.panelClockMs = Date.now()", "root.expireStaleUsage(root.panelClockMs)"):
            if not code_contains(panel_clock_body, fragment):
                raise AssertionError("the panel clock must update time and expire usage even without automatic refresh")

    def test_provider_presentation_metadata(self):
        snapshot_text = (root / "contents/ui/ProviderSnapshot.js").read_text()

        normalize_provider_body = function_body(snapshot_text, "normalize")
        present_provider_body = function_body(main_text, "presentProviderSnapshot")
        for fragment in ("statusKnown: snapshot.statusRecord !== null", "title: Normalizer.boundedDisplayText(",
                         "status: Normalizer.boundedDisplayText(", "usageReceivedAtMs: snapshot.usageReceivedAtMs"):
            if not code_contains(present_provider_body, fragment):
                raise AssertionError("provider presentation must retain bounded metadata and original receipt time")
        for fragment in ('var lanes = ["primary", "secondary", "tertiary"]',
                         "windowSnapshot(usage[lane], pace[lane], true, lane, null, receivedAtMs)",
                         "Array.isArray(usage.extraRateWindows)", "Math.min(extras.length, Normalizer.maximumExtraRateWindows)"):
            if not code_contains(normalize_provider_body, fragment):
                raise AssertionError("normalized windows must preserve CLI lanes and bound extra records")


if __name__ == "__main__":
    unittest.main()
