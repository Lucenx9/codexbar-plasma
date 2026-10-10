import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import "components" as Components
import "controllers" as Controllers
import "AiInsights.js" as AiInsights
import "AiInsightsSnapshot.js" as AiInsightsSnapshot
import "Guards.js" as Guards
import "NotificationMemo.js" as NotificationMemo
import "NotificationPlanner.js" as NotificationPlanner
import "PacePresentation.js" as PacePresentation
import "PanelDisplay.js" as PanelDisplay
import "PanelElements.js" as PanelElements
import "PanelProviders.js" as PanelProviders
import "PanelRules.js" as PanelRules
import "PopupHiddenRows.js" as PopupHiddenRows
import "PopupHiddenSections.js" as PopupHiddenSections
import "PopupSelection.js" as PopupSelection
import "ProviderAutoSelect.js" as ProviderAutoSelect
import "ProviderSnapshot.js" as ProviderSnapshot
import "CostPresentation.js" as CostPresentation
import "ShareUsage.js" as ShareUsage
import "OverviewProviders.js" as OverviewProviders
import "ProviderIdentity.js" as ProviderIdentity
import "PrivacyPresentation.js" as PrivacyPresentation
import "ProviderNormalizer.js" as Normalizer
import "ProviderOrder.js" as ProviderOrder
import "UsageCache.js" as UsageCache
import "QuotaThresholds.js" as QuotaThresholds
import "SafeText.js" as SafeText
import "ThemeContrast.js" as ThemeContrast
import "UpdateLogic.js" as UpdateLogic

PlasmoidItem {
    id: root

    Plasmoid.icon: "view-statistics"
    Plasmoid.title: "CodexBar"
    toolTipMainText: Plasmoid.title
    toolTipSubText: panelToolTipText()
    toolTipTextFormat: Text.PlainText
    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh")
            icon.name: "view-refresh"
            onTriggered: root.refreshNow(true)
        }
    ]

    property string commandPath: (Plasmoid.configuration.commandPath || "codexbar").trim()
    property string provider: (Plasmoid.configuration.provider || "").trim()
    property string source: (Plasmoid.configuration.source || "").trim()
    property int refreshIntervalSec: isFinite(Number(Plasmoid.configuration.refreshInterval)) ? Math.max(0, Number(Plasmoid.configuration.refreshInterval)) : 300
    property bool includeStatus: Plasmoid.configuration.includeStatus
    property bool refreshOnOpen: Plasmoid.configuration.refreshOnOpen === true
    property bool showPopupPace: Plasmoid.configuration.showPopupPace !== false
    property bool showPopupCredits: Plasmoid.configuration.showPopupCredits !== false
    property bool showPopupProviderDetails: Plasmoid.configuration.showPopupProviderDetails !== false
    property bool privacyMode: Plasmoid.configuration.privacyMode === true
    readonly property bool aiInsightsEnabled: Plasmoid.configuration.aiInsightsEnabled === true
    // Translators set this marker to their catalog's language tag, so insights
    // follow the catalog i18n() actually resolved rather than the numeric or
    // regional locale, which can differ from the interface language.
    readonly property string aiInsightsLanguage: aiInsightsLanguageTag()
    // Built only while enabled; disabled installations do no AI work at all.
    readonly property var aiInsightsSnapshot: aiInsightsEnabled
        ? AiInsightsSnapshot.build(providers, panelClockMs, quotaWarningPercent)
        : ({ text: "", id: "", sufficient: false })
    readonly property var aiInsightsCache: aiInsightsEnabled
        ? AiInsights.parseCache(Plasmoid.configuration.aiInsightsCache || "") : null
    readonly property string aiInsightsCacheState: AiInsights.cacheState(aiInsightsCache,
        aiInsightsController.contextKey, panelClockMs, aiInsightsController.intervalHours)
    readonly property bool aiInsightsConfigured: aiInsightsController.configured
    readonly property bool aiInsightsBusy: aiInsightsController.busy
    readonly property string aiInsightsErrorReason: aiInsightsController.errorReason
    readonly property var presentedProviders: providerPresentations(providers)
    readonly property var presentedOverviewProviders: providerPresentations(overviewProviderItems)
    readonly property var presentedSessions: sessions.map(function(item) {
        return PrivacyPresentation.session(item, privacyMode)
    })
    readonly property var presentedProviderData: providerPresentation(selectedProviderData)
    property bool costUsageEnabled: Plasmoid.configuration.costUsageEnabled !== false
    property int costHistoryDays: isFinite(Number(Plasmoid.configuration.costHistoryDays)) ? Math.max(1, Math.min(365, Number(Plasmoid.configuration.costHistoryDays))) : 30
    // A calendar period replaces the day window until a day count is chosen
    // again, here or in the settings.
    readonly property string costHistoryPeriod: CostPresentation.costPeriod(Plasmoid.configuration.costHistoryPeriod)
    // The cost payload already carries per-day tokens next to per-day cost, so
    // switching the plotted metric never needs a second CLI call.
    property string costHistoryMetric: safeCostHistoryMetric(Plasmoid.configuration.costHistoryMetric)
    readonly property bool costHistoryShowsTokens: costHistoryMetric === "tokens"
    // Resolved once: a .pragma library module cannot reach Qt.locale().
    readonly property var costNumberFormat: CostPresentation.numberFormat(
        Qt.locale().groupSeparator, Qt.locale().decimalPoint)
    property bool usageBarsShowUsed: Plasmoid.configuration.usageBarsShowUsed !== false
    property bool showQuotaWarningMarkers: Plasmoid.configuration.showQuotaWarningMarkers !== false
    readonly property int quotaWarningPercent: QuotaThresholds.warningPercent(
        Plasmoid.configuration.quotaWarningPercent)
    // Derived from the warning step so a critical threshold configured below it
    // can never make the "major" level unreachable.
    readonly property int quotaCriticalPercent: QuotaThresholds.criticalPercent(
        quotaWarningPercent,
        Plasmoid.configuration.quotaCriticalPercent)
    property bool enableNotifications: Plasmoid.configuration.enableNotifications !== false
    property bool notifyStatusIncidents: Plasmoid.configuration.notifyStatusIncidents !== false
    property bool notifyQuotaWarnings: Plasmoid.configuration.notifyQuotaWarnings !== false
    property bool notifyPredictivePaceWarnings: Plasmoid.configuration.notifyPredictivePaceWarnings === true
    property bool notifyLimitResets: Plasmoid.configuration.notifyLimitResets === true
    property string menuBarDisplayMode: safeMenuBarDisplayMode(Plasmoid.configuration.menuBarDisplayMode)
    property bool showPopupTabLabels: Plasmoid.configuration.showPopupTabLabels !== false
    property string providerOrderRaw: Plasmoid.configuration.providerOrder || ""
    property string panelProviderIDsRaw: Plasmoid.configuration.panelProviderIDs || ""
    property string panelElementOrderRaw: Plasmoid.configuration.panelElementOrder || ""
    readonly property bool minimalPanel: Plasmoid.configuration.panelStyle === "minimal"
    readonly property string panelQuotaLane: PanelDisplay.safeLane(Plasmoid.configuration.panelQuotaLane)
    readonly property var panelVisibilityRules: PanelRules.normalizedRules(Plasmoid.configuration.panelVisibilityRules)
    property bool resetTimesShowAbsolute: Plasmoid.configuration.resetTimesShowAbsolute === true
    property bool showProviderChangelogs: Plasmoid.configuration.showProviderChangelogs === true
    property bool autoSelectProvider: Plasmoid.configuration.autoSelectProvider === true
    property string overviewProviderIDsRaw: Plasmoid.configuration.overviewProviderIDs || ""
    readonly property var popupHiddenUsageRows: PopupHiddenRows.parse(Plasmoid.configuration.popupHiddenUsageRows || "")
    readonly property var popupHiddenDetailSections: PopupHiddenSections.parse(Plasmoid.configuration.popupHiddenDetailSections || "")
    property int providerConfigRevision: boundedConfigRevision(Plasmoid.configuration.providerConfigRevision)
    property var providers: []
    readonly property var providerDisplayNames: usageController.providerDisplayNames
    readonly property string errorText: usageController.errorText
    readonly property bool commandPathFailed: usageController.commandPathFailed
    property string lastUpdatedText: ""
    property bool usageLifecycleInitialized: false
    readonly property string usageIdentityContext: JSON.stringify([
        commandPath, provider, source, providerConfigRevision])
    readonly property bool loading: usageController.loading
    // Reset labels and run-out durations keep moving even when automatic CLI
    // refresh is disabled. Each row's receipt time anchors forecast durations;
    // unrelated refreshes must not restart that countdown.
    property double panelClockMs: Date.now()
    readonly property int panelClockIntervalMs: 60000
    readonly property string commandSource: usageController.commandSource
    property string providerConfigStamp: ""
    readonly property int maximumCostHistoryPoints: Normalizer.maximumCostHistoryPoints
    readonly property bool costLoading: costController.loading
    readonly property var tokenCosts: presentTokenCosts(costController.costs)
    property var costTrustNoticeStates: ({})
    readonly property string costErrorText: costController.errorText
    readonly property var sessions: sessionsController.sessions
    readonly property string sessionsErrorText: sessionsController.errorText
    readonly property string sessionsLastUpdatedText: sessionsController.lastUpdatedAtMs >= 0
        ? i18n("Updated %1", timeLabels.clockTime(sessionsController.lastUpdatedAtMs)) : ""
    readonly property bool sessionsLoading: sessionsController.loading
    property string selectedProviderID: ""
    // Provider meter currently under the panel pointer. The plasmoid tooltip
    // narrows to this provider while it is set, so hovering one panel icon
    // reports only that provider instead of the whole roster.
    property string hoveredPanelProviderID: ""
    property string selectedGlobalView: "overview"
    property bool selectionInitialized: false
    property var selectedAccounts: ({})
    readonly property var accountOptions: presentAccountOptions(accountsController.options)
    property var notificationMemo: ({})
    property var notificationRefreshPending: ({})
    property bool notificationsPrimed: false
    readonly property bool verticalFormFactor: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property var overviewProviderItems: overviewProviders()
    readonly property bool globalNavigationAvailable: provider.length === 0
    readonly property bool overviewAvailable: globalNavigationAvailable && providers.length > 1 && overviewProviderItems.length > 0
    readonly property bool spendAvailable: globalNavigationAvailable && costUsageEnabled
    readonly property bool sessionsAvailable: globalNavigationAvailable
    readonly property int selectedProviderIndex: providerIndexForID(selectedProviderID)
    readonly property bool globalViewSelected: selectionInitialized && selectedProviderID.length === 0
    readonly property bool overviewSelected: overviewAvailable && globalViewSelected && selectedGlobalView === "overview"
    readonly property bool spendSelected: spendAvailable && globalViewSelected && selectedGlobalView === "spend"
    readonly property bool sessionsSelected: sessionsAvailable && globalViewSelected && selectedGlobalView === "sessions"
    readonly property bool providerUsageFeedbackVisible: !spendSelected && !sessionsSelected
    readonly property var selectedProviderData: providers.length > 0 && selectedProviderIndex >= 0
        ? providers[Math.min(selectedProviderIndex, providers.length - 1)]
        : null
    readonly property real roundedSurfaceRadius: Kirigami.Units.cornerRadius
        + Kirigami.Units.smallSpacing
    // Radius for a small surface drawn inside a roundedSurfaceRadius container.
    // Concentric rounding wants the inner radius reduced by the inset between
    // the two edges, and popup surfaces inset their content by smallSpacing, so
    // this is roundedSurfaceRadius minus that inset by construction.
    readonly property real nestedSurfaceRadius: Kirigami.Units.cornerRadius
    // Two-step de-emphasis scale for popup text. A supporting label uses the
    // secondary step and the value it annotates uses the stronger step, so a
    // label/value pair keeps its hierarchy without inventing a new opacity per
    // section. 0.7 is the lowest step where Kirigami.Theme.textColor still
    // clears WCAG AA 4.5:1 against the Breeze Light popup background.
    readonly property real secondaryTextOpacity: 0.7
    readonly property real valueTextOpacity: 0.85
    // Shared track height for the credits, cost, and usage meters that stack in
    // one provider detail view. Derived from gridUnit so it follows the user
    // font size instead of pinning a device pixel count.
    readonly property real meterTrackHeight: Math.round(Kirigami.Units.gridUnit * 0.4)
    // Thinner track for meters that sit inside a scannable list row (overview
    // rows, cost history rows) instead of leading a detail section. Keeping the
    // two scales apart is what makes the primary meters read as primary.
    readonly property real compactMeterTrackHeight: Math.round(Kirigami.Units.gridUnit * 0.28)

    onUsageIdentityContextChanged: {
        invalidateUsageData()
        scheduleUsageRefresh()
    }
    onProviderOrderRawChanged: providers = ProviderOrder.orderedItems(
        providers, providerOrderRaw)
    onCostHistoryDaysChanged: applyTokenCosts()
    onTokenCostsChanged: applyTokenCosts()
    onAutoSelectProviderChanged: updateSelectedProvider()
    onOverviewProviderIDsRawChanged: updateSelectedProvider()
    onOverviewAvailableChanged: reconcileGlobalViewAvailability()
    onSpendAvailableChanged: reconcileGlobalViewAvailability()
    onSessionsAvailableChanged: reconcileGlobalViewAvailability()
    onEnableNotificationsChanged: resetNotificationMemo()
    onNotifyStatusIncidentsChanged: resetNotificationMemo()
    onNotifyQuotaWarningsChanged: resetNotificationMemo()
    onNotifyPredictivePaceWarningsChanged: resetNotificationMemo()
    // The memo stores the level each row was last observed at. Keeping it across
    // a threshold change would suppress a warning the new lower threshold should
    // raise, and leave a row armed at a level the new higher threshold no longer
    // reaches.
    onQuotaWarningPercentChanged: resetNotificationMemo()
    onQuotaCriticalPercentChanged: resetNotificationMemo()
    onNotifyLimitResetsChanged: resetNotificationMemo()
    onProvidersChanged: {
        if (providers.length === 0) {
            hoveredPanelProviderID = ""
            updateSelectedProvider()
            resetNotificationMemo()
            return
        }
        if (hoveredPanelProviderID.length > 0 && providerIndexForID(hoveredPanelProviderID) < 0) {
            hoveredPanelProviderID = ""
        }
        updateSelectedProvider()
        Qt.callLater(processNotifications)
    }

    Component.onCompleted: {
        usageLifecycleInitialized = true
        forgetInstalledWidgetUpdate()
        Qt.callLater(serviceWidgetUpdateRequest)
    }

    function safeMenuBarDisplayMode(value) {
        return PanelDisplay.safeMode(value)
    }

    function safeCostHistoryMetric(value) {
        return String(value || "cost") === "tokens" ? "tokens" : "cost"
    }

    function panelElementOrder() {
        return PanelElements.normalizedOrder(panelElementOrderRaw)
    }

    function boundedConfigRevision(value) {
        var revision = Number(value)
        if (!isFinite(revision)) {
            return 0
        }
        return Math.max(0, Math.min(2147480000, Math.floor(revision)))
    }

    function boundedCliMessage(value) {
        return SafeText.cliMessage(SafeText.stripLoaderDiagnostics(value), SafeText.maximumCliMessageLength)
    }

    function isCliRecord(value) {
        return Normalizer.isCliRecord(value)
    }

    function normalizedProviderID(value) {
        return Normalizer.normalizedProviderID(value)
    }

    function hasOwnKey(item, key) {
        return Guards.hasOwnKey(item, key)
    }

    function isUnsafeObjectKey(key) {
        return Guards.isUnsafeObjectKey(key)
    }

    function providerMapKey(providerID) {
        return Normalizer.providerSnapshotKey(providerID)
    }

    function refreshNow(bypassProviderRosterCache) {
        usageController.refresh(bypassProviderRosterCache)
    }

    function scheduleUsageRefresh() {
        usageController.scheduleRefresh()
    }

    function retryUsage() {
        if (!loading) {
            root.refreshNow(true)
        }
    }

    function markUsageSnapshotReceived() {
        var nowMs = Date.now()
        panelClockMs = nowMs
    }

    function usageCacheContext() {
        if (providerConfigStamp.length === 0 || commandSource.length === 0) {
            return ""
        }
        var accounts = Object.keys(selectedAccounts).sort().map(function(key) {
            return [key, root.selectedAccounts[key]]
        })
        return Qt.md5(JSON.stringify([usageIdentityContext, accounts, providerConfigStamp]))
    }

    function invalidateUsageData(providerID) {
        if (!usageLifecycleInitialized) {
            return
        }
        usageController.reset()
        providers = providerID ? providers.map(function(item) {
            return item.provider === providerID ? root.normalizeProvider({ provider: providerID }) : item
        }) : []
        // A single-provider reset must not discard healthy providers'
        // persisted quotas; rewrite the disk cache from what remains.
        var context = usageCacheContext()
        if (context.length > 0) {
            Plasmoid.configuration.usageCache = UsageCache.encode(providers, context, Date.now())
        } else if (!providerID) {
            Plasmoid.configuration.usageCache = ""
        }
        if (!providerID) {
            accountsController.reset()
        }
        lastUpdatedText = ""
    }

    function restoreUsageCache() {
        var context = usageCacheContext()
        if (context.length === 0) {
            return
        }
        var nowMs = Date.now()
        var restored = UsageCache.decode(Plasmoid.configuration.usageCache, context, nowMs)
        var cachedProviders = restored.map(function(payload) {
            var item = root.normalizeProvider(payload)
            item.lastGoodAtMs = Date.parse(payload.usage.updatedAt)
            item.usageStale = true
            item.tokenCost = null
            return item
        })
        var merged = UsageCache.restore(cachedProviders, providers, nowMs, selectedAccounts)
        if (merged.length === 0) {
            Plasmoid.configuration.usageCache = UsageCache.encode(providers, context, nowMs)
            return
        }
        providers = ProviderOrder.orderedItems(merged, providerOrderRaw)
        Plasmoid.configuration.usageCache = UsageCache.encode(providers, context, nowMs)
        if (providers.some(function(item) { return item.usageStale === true })) {
            lastUpdatedText = i18n("Showing last known usage")
        }
    }

    function commitUsageSnapshot(items) {
        var nowMs = Date.now()
        var nextProviders = UsageCache.reconcile(providers, items, nowMs)
        markNotificationProvidersFresh(nextProviders)
        var hasFreshUsage = nextProviders.some(function(item) { return !item.usageStale && item.error.length === 0 })
        if (hasFreshUsage) {
            markUsageSnapshotReceived()
        }
        providers = nextProviders
        lastUpdatedText = nextProviders.some(function(item) { return item.usageStale === true })
            ? i18n("Showing last known usage")
            : hasFreshUsage ? i18n("Updated %1", timeLabels.clockTime(nowMs)) : ""
        var context = usageCacheContext()
        if (context.length > 0) {
            Plasmoid.configuration.usageCache = UsageCache.encode(nextProviders, context, nowMs)
        }
    }

    function failUsageRefresh(message) {
        var nowMs = Date.now()
        var failures = providers.map(function(item) {
            return root.normalizeProvider(root.providerErrorPayload(item.provider, message))
        })
        providers = UsageCache.reconcile(providers, failures, nowMs)
        lastUpdatedText = providers.some(function(item) { return item.usageStale === true })
            ? i18n("Showing last known usage") : ""
        var context = usageCacheContext()
        if (context.length > 0) {
            Plasmoid.configuration.usageCache = UsageCache.encode(providers, context, nowMs)
        }
        panelClockMs = nowMs
    }

    function expireStaleUsage(nowMs) {
        var expired = UsageCache.expiredProviderIDs(providers, nowMs)
        if (expired.length === 0) {
            return
        }
        providers = providers.map(function(item) {
            if (expired.indexOf(item.provider) < 0) {
                return item
            }
            var replacement = UsageCache.withCurrentStatus(root.normalizeProvider(root.providerErrorPayload(item.provider,
                item.error || i18n("Cached usage has expired. Refresh to try again."))), item)
            // withCurrentStatus copies a fresh error snapshot, which carries
            // no measurement contract; expired quotas keep no measurement.
            replacement.lastGoodAtMs = 0
            replacement.usageStale = false
            return replacement
        })
        if (!providers.some(function(item) { return item.usageStale === true })) {
            lastUpdatedText = ""
        }
        var context = usageCacheContext()
        if (context.length > 0) {
            Plasmoid.configuration.usageCache = UsageCache.encode(providers, context, nowMs)
        }
    }

    function lastGoodUsageText(item) {
        var ageSeconds = Math.max(0, (panelClockMs - item.lastGoodAtMs) / 1000)
        return ageSeconds < 60 ? i18n("Last known usage, just now")
            : i18n("Last known usage, %1 ago", paceEtaText(ageSeconds))
    }

    function providerUsageTimestamp(item) {
        if (!item || !(item.lastGoodAtMs > 0)) {
            return ""
        }
        return item.usageStale === true ? lastGoodUsageText(item)
            : i18n("Updated %1", timeLabels.clockTime(item.lastGoodAtMs))
    }

    function handleProviderConfigObservation(stamp, initial) {
        providerConfigStamp = stamp
        if (initial) {
            restoreUsageCache()
            return
        }
        invalidateUsageData()
        scheduleUsageRefresh()
    }

    function refreshCost(force) {
        return costController.refresh(force)
    }

    function refreshSpendIfStale() {
        if (!spendSelected || !expanded) {
            return false
        }
        return costController.refresh(false)
    }

    function refreshSessions() {
        return sessionsController.refresh()
    }

    function providerErrorPayload(providerID, message) {
        return {
            provider: providerID,
            source: source.length > 0 ? source : "auto",
            error: {
                code: 1,
                kind: "provider",
                message: message
            }
        }
    }

    function loadAccounts(providerID) {
        return accountsController.load(providerID)
    }

    // Every session runs on the same machine unless the CLI reports more than
    // one host, so a repeated host name would only add noise to each card.
    readonly property bool sessionHostsVary: {
        var firstHost = ""
        for (var i = 0; i < sessions.length; i++) {
            var host = sessions[i].host
            if (host.length === 0) {
                continue
            }
            if (firstHost.length === 0) {
                firstHost = host
            } else if (host !== firstHost) {
                return true
            }
        }
        return false
    }

    // "Just now", "5 minutes ago", "2 days ago": the popup's relative age.
    function elapsedText(sinceMs, nowMs) {
        var currentTimeMs = Number(nowMs)
        if (!isFinite(currentTimeMs) || currentTimeMs <= 0) {
            currentTimeMs = Date.now()
        }
        var elapsedSeconds = Math.max(0, Math.floor((currentTimeMs - sinceMs) / 1000))
        if (elapsedSeconds < 60) {
            return i18n("Just now")
        }
        var minutes = Math.floor(elapsedSeconds / 60)
        if (minutes < 60) {
            return i18np("%1 minute ago", "%1 minutes ago", minutes)
        }
        var hours = Math.floor(minutes / 60)
        if (hours < 24) {
            return i18np("%1 hour ago", "%1 hours ago", hours)
        }
        var days = Math.floor(hours / 24)
        return i18np("%1 day ago", "%1 days ago", days)
    }

    function presentTokenCosts(snapshots) {
        return costText.presentTokenCosts(snapshots)
    }

    function costHistoryWindowLabel(item, requestedHistoryDays) {
        return costText.costHistoryWindowLabel(item, requestedHistoryDays)
    }

    function costChartPoints(points, memo) {
        return CostPresentation.memoizedChartPoints(memo, costNumberFormat, points, costHistoryShowsTokens)
    }

    property var shareUsageSnapshot: null
    readonly property var shareUsageWindow: shareUsageLoader.item

    function openShareUsage() {
        var costs = spendProviderCosts()
        if (costs.length === 0 || costLoading) return
        if (shareUsageWindow) shareUsageWindow.close()
        shareUsageSnapshot = ShareUsage.snapshot(costs, costHistoryDays,
            new Date().toISOString(), costErrorText.length > 0, costHistoryPeriod)
        shareUsageLoader.active = true
        shareUsageWindow.show()
        shareUsageWindow.raise()
        shareUsageWindow.requestActivate()
    }

    Loader {
        id: shareUsageLoader
        active: false
        sourceComponent: Components.ShareUsageWindow {
            snapshot: root.shareUsageSnapshot
            applet: root
        }
    }

    function spendProviderCosts() {
        var snapshots = CostPresentation.spendSnapshots(tokenCosts, costHistoryDays, function(providerID) {
            return providerTitle(providerID)
        }, costHistoryPeriod)
        return snapshots.map(function(item) { return root.costPresentation(item) })
    }

    function presentedSpendProviderCosts(costs) {
        return ProviderOrder.orderedItems(costs || spendProviderCosts(), providerOrderRaw)
    }

    function spendDailyPoints() {
        return CostPresentation.spendDailyPoints(costNumberFormat, spendProviderCosts(), costHistoryShowsTokens)
    }

    function spendCurrency(costs) {
        return CostPresentation.spendCurrency(costs || spendProviderCosts())
    }

    function spendTotalLine() {
        return costText.spendTotalLine(spendProviderCosts())
    }

    function updateCostTrustNoticeState(scope, summary, shouldDismiss) {
        var transition = CostPresentation.costTrustNoticeStoreTransition(
            summary, costTrustNoticeStates, scope, shouldDismiss)
        costTrustNoticeStates = transition.states
        return transition.state
    }

    function setCostHistoryDays(days) {
        var nextDays = Math.max(1, Math.min(maximumCostHistoryPoints, Math.floor(Number(days) || 30)))
        Plasmoid.configuration.costHistoryDays = nextDays
        Plasmoid.configuration.costHistoryPeriod = ""
    }

    function setCostHistoryPeriod(period) {
        Plasmoid.configuration.costHistoryPeriod = CostPresentation.costPeriod(period)
    }

    function setCostHistoryMetric(metric) {
        Plasmoid.configuration.costHistoryMetric = safeCostHistoryMetric(metric)
    }

    // The CLI reports whether its local log scan already covers the requested
    // window; until it does, the earliest bars are short for a scan reason
    // rather than a spend reason.
    function spendHistoryStillBuilding() {
        return CostPresentation.historyStillBuilding(spendProviderCosts())
    }

    function dashboardLabelText(labelKey) {
        return costText.dashboardLabelText(labelKey)
    }

    function dashboardPartText(part) {
        return costText.dashboardPartText(part)
    }

    function dashboardDisplayRow(row) {
        return costText.dashboardDisplayRow(row)
    }

    function providerTokenCost(providerID) {
        var key = providerMapKey(providerID)
        if (key.length === 0) {
            return null
        }
        var snapshot = tokenCosts[key] || null
        return CostPresentation.snapshotMatchesRange(snapshot, costHistoryDays, costHistoryPeriod)
            ? snapshot
            : null
    }

    function applyTokenCosts() {
        if (!providers || providers.length === 0) {
            return
        }

        var nextProviders = []
        for (var i = 0; i < providers.length; i++) {
            var item = copyObject(providers[i])
            item.tokenCost = item.usageStale === true ? null : providerTokenCost(item.provider)
            nextProviders.push(item)
        }
        providers = nextProviders
    }

    function selectedAccountForProvider(providerID) {
        var key = providerMapKey(providerID)
        if (key.length === 0) {
            return ""
        }
        var selected = selectedAccounts[key]
        return selected ? String(selected) : ""
    }

    function accountOptionsForProvider(providerID) {
        var key = providerMapKey(providerID)
        if (key.length === 0) {
            return []
        }
        return accountOptions[key] || []
    }

    function accountErrorForProvider(providerID) {
        var key = providerMapKey(providerID)
        if (key.length === 0) {
            return ""
        }
        return privateErrorText(accountsController.errorForProvider(key))
    }

    function accountLoadingForProvider(providerID) {
        var key = providerMapKey(providerID)
        return key.length > 0 && accountsController.loadingForProvider(key)
    }

    function privateErrorText(text) {
        return PrivacyPresentation.errorText(text, privacyMode,
            i18n("Details hidden by privacy mode."))
    }

    function accountDisplayLabel(item, index) {
        return privacyMode ? i18n("Account %1", index + 1) : accountLabel(item)
    }

    function costPresentation(item) {
        var result = PrivacyPresentation.cost(item, privacyMode)
        if (!privacyMode || !result) {
            return result
        }
        result.title = i18n("Cost")
        result.sessionLine = costLine(i18n("Today"), result.today.cost,
            result.today.tokens, result.today.currency)
        var trust = CostPresentation.costTrustSummary([result])
        result.valueMode = trust ? trust.valueMode : "plain"
        result.windowLabel = costHistoryWindowLabel(result, result.historyDays)
        result.monthLine = costLine(result.windowLabel,
            result.totals.cost, result.totals.tokens, result.totals.currency,
            result.valueMode)
        result.windowValueLine = costValueLine(result.totals.cost, result.totals.tokens,
            result.totals.currency, result.valueMode)
        result.hintLine = tokenCostHint(result.provider)
        for (var i = 0; i < result.models.length; i++) {
            result.models[i].label = i18n("Model %1", i + 1)
        }
        for (var rankIndex = 0; rankIndex < result.tokenRanking.rows.length; rankIndex++) {
            result.tokenRanking.rows[rankIndex].label = i18n("Model %1", rankIndex + 1)
        }
        for (var dayIndex = 0; dayIndex < result.daily.length; dayIndex++) {
            var dayModels = result.daily[dayIndex].models
            for (var modelIndex = 0; modelIndex < dayModels.length; modelIndex++) {
                dayModels[modelIndex].label = i18n("Model %1", modelIndex + 1)
            }
        }
        for (var j = 0; j < result.projects.rows.length; j++) {
            result.projects.rows[j].label = i18n("Project %1", j + 1)
        }
        return result
    }

    function providerPresentations(items) {
        return items.map(function(item) { return root.providerPresentation(item) })
    }

    function providerPresentation(item) {
        if (!privacyMode || !item) {
            return item
        }
        var result = PrivacyPresentation.provider(item, true, {
            title: providerDisplayTitle(item.provider),
            account: i18n("Account hidden"),
            status: statusBadgeText(item.statusSeverity),
            error: i18n("Details hidden by privacy mode."),
            placeholder: i18n("No usage yet"),
            usage: i18n("Usage"),
            rowLabels: (item.rows || []).map(function(row) {
                return rateWindowLabels.labelForLane(providerKey(item.provider), row.lane)
            })
        })
        result.tokenCost = costPresentation(item.tokenCost)
        return result
    }

    // Hidden rows and sections filter only the provider tab; fetching, alerts,
    // the panel and the Overview summary keep their unfiltered data.
    function popupDetailSections(item) {
        return item ? PopupHiddenSections.visibleSections(item.providerDetails, popupHiddenDetailSections, item.provider) : []
    }

    function hiddenPopupDetailSections(item) {
        return item ? PopupHiddenSections.hiddenSections(item.providerDetails, popupHiddenDetailSections, item.provider) : []
    }

    function popupDetailSectionHideable(section) {
        return PopupHiddenSections.sectionKey(section).length > 0
            && popupHiddenDetailSections.length < PopupHiddenSections.maximumEntries
    }

    function hidePopupDetailSection(providerID, section) {
        Plasmoid.configuration.popupHiddenDetailSections = PopupHiddenSections.serialize(
            PopupHiddenSections.hidden(popupHiddenDetailSections, providerID, PopupHiddenSections.sectionKey(section)))
    }

    function restorePopupDetailSection(providerID, section) {
        Plasmoid.configuration.popupHiddenDetailSections = PopupHiddenSections.serialize(
            PopupHiddenSections.restored(popupHiddenDetailSections, providerID, PopupHiddenSections.sectionKey(section)))
    }

    function popupUsageRows(item) {
        return item ? PopupHiddenRows.visibleRows(item.rows, popupHiddenUsageRows, item.provider) : []
    }

    function hiddenPopupUsageRows(item) {
        return item ? PopupHiddenRows.hiddenRows(item.rows, popupHiddenUsageRows, item.provider) : []
    }

    function popupUsageRowHideable(row) {
        return PopupHiddenRows.rowKey(row).length > 0
            && popupHiddenUsageRows.length < PopupHiddenRows.maximumEntries
    }

    function hidePopupUsageRow(providerID, row) {
        var key = PopupHiddenRows.rowKey(row)
        if (key.length > 0) {
            Plasmoid.configuration.popupHiddenUsageRows = PopupHiddenRows.serialize(
                PopupHiddenRows.hidden(popupHiddenUsageRows, providerID, key))
        }
    }

    function restorePopupUsageRow(providerID, row) {
        var key = PopupHiddenRows.rowKey(row)
        if (key.length > 0) {
            Plasmoid.configuration.popupHiddenUsageRows = PopupHiddenRows.serialize(
                PopupHiddenRows.restored(popupHiddenUsageRows, providerID, key))
        }
    }

    function accountLabel(item) {
        return Normalizer.accountLabel(item)
    }

    // The stable `--account` identity. Display labels may collapse spacing
    // that still distinguishes two accounts, so selection, matching, and the
    // CLI argument compare keys, never labels.
    function accountKey(item) {
        return Normalizer.accountKey(item)
    }

    function accountSubtitle(item) {
        if (privacyMode || !item) {
            return ""
        }
        var parts = []
        if (item.loginMethod && item.loginMethod.length > 0) {
            parts.push(item.loginMethod)
        }
        if (item.organization && item.organization.length > 0 && item.organization !== item.account) {
            parts.push(item.organization)
        }
        return parts.join(" · ")
    }

    function accountIsSelected(option, currentItem) {
        if (!option) {
            return false
        }
        var identity = accountKey(option)
        var selected = selectedAccountForProvider(option.provider)
        if (selected.length > 0) {
            return identity.length > 0 && identity === selected
        }
        // A presented snapshot may replace the account label with a placeholder.
        // Selection always compares against the original account identity.
        var currentIndex = currentItem ? providerIndexForID(currentItem.provider) : -1
        var accountItem = currentIndex >= 0 ? providers[currentIndex] : currentItem
        return accountItem && accountItem.provider === option.provider && identity.length > 0 && identity === accountKey(accountItem)
    }

    function selectAccount(providerID, accountIdentity) {
        var key = providerMapKey(providerID)
        if (key.length === 0) {
            return
        }
        var identity = String(accountIdentity || "")
        var next = copyObject(selectedAccounts)
        if (identity.length > 0) {
            next[key] = identity
        } else {
            delete next[key]
        }
        invalidateUsageData(key)
        selectedAccounts = next
        setNotificationProviderRefreshPending(key, true)

        var options = accountOptionsForProvider(key)
        for (var i = 0; i < options.length; i++) {
            if (root.accountKey(options[i]) === identity) {
                replaceProviderSnapshot(key, options[i])
                scheduleUsageRefresh()
                return
            }
        }
        // Coalesce this request with the controller's changed account inputs.
        scheduleUsageRefresh()
    }

    function replaceProviderSnapshot(providerID, snapshot) {
        var key = providerMapKey(providerID)
        if (key.length === 0) {
            return
        }
        var replacement = UsageCache.reconcile([], [snapshot], Date.now())[0]
        replacement.tokenCost = replacement.usageStale === true ? null : providerTokenCost(key)
        var nextProviders = []
        for (var i = 0; i < providers.length; i++) {
            nextProviders.push(providers[i].provider === key ? replacement : providers[i])
        }
        if (!nextProviders.some(function(item) { return item.provider === key })) {
            nextProviders.push(replacement)
        }
        providers = ProviderOrder.orderedItems(nextProviders, providerOrderRaw)
    }

    function presentAccountOptions(options) {
        var result = ({})
        var keys = Object.keys(options)
        for (var i = 0; i < keys.length; i++) {
            result[keys[i]] = options[keys[i]].map(function(item) {
                return root.presentProviderSnapshot(item)
            })
        }
        return result
    }

    function normalizeProvider(item) {
        return presentProviderSnapshot(ProviderSnapshot.normalize(item, Date.now()))
    }

    function presentProviderSnapshot(snapshot) {
        var providerID = snapshot.provider
        var rows = snapshot.rows.map(function(row) { return root.presentUsageWindow(row, providerID) })
        var dashboard = snapshot.usageDashboard
        return {
            provider: providerID,
            title: Normalizer.boundedDisplayText(providerTitle(providerID,
                snapshot.displayName === null ? providerDisplayNames[providerID] : snapshot.displayName), 120),
            source: snapshot.source,
            version: snapshot.version,
            account: snapshot.account,
            organization: snapshot.organization,
            loginMethod: snapshot.loginMethod,
            accountKey: snapshot.accountKey,
            rows: rows,
            primaryRow: rows.length > 0 && rows[0].lane === "primary" ? rows[0] : null,
            providerDetails: snapshot.providerDetails,
            usageDashboard: dashboard ? {kpis: dashboard.kpis.map(dashboardDisplayRow), rows: dashboard.rows.map(dashboardDisplayRow)} : null,
            providerCost: providerCostSection(providerID, snapshot.providerCost),
            resetCredits: resetCreditsSection(providerID, snapshot.resetCredits),
            tokenCost: providerTokenCost(providerID),
            codexCreditLimit: snapshot.codexCreditLimit,
            planText: Normalizer.boundedDisplayText(planText(providerID, snapshot.planMethod), 120),
            dashboardUrl: providerDashboardUrl(providerID),
            statusUrl: safeStatusUrl(providerID, snapshot.statusUrl),
            changelogUrl: providerChangelogUrl(providerID),
            credits: snapshot.credits,
            status: Normalizer.boundedDisplayText(snapshot.statusRecord ? statusText(snapshot.statusRecord) : "", 500),
            statusKnown: snapshot.statusRecord !== null,
            statusSeverity: snapshot.statusSeverity,
            statusIncidentKey: snapshot.statusIncidentKey,
            hasIncident: snapshot.statusSeverity.length > 0,
            error: snapshot.commandFailed ? (snapshot.error || i18n("codexbar command failed.")) : "",
            placeholder: snapshot.placeholder === "limitsUnavailable" ? i18n("Limits not available")
                : (snapshot.placeholder === "noUsage" ? i18n("No usage yet") : ""),
            usageReceivedAtMs: snapshot.usageReceivedAtMs,
            updatedAt: snapshot.updatedAt
        }
    }

    function presentUsageWindow(snapshot, providerID) {
        var row = copyObject(snapshot)
        row.label = snapshot.label !== null ? snapshot.label
            : (snapshot.lane === "extra" ? i18n("Extra") : rateWindowLabels.labelForLane(providerKey(providerID), snapshot.lane, snapshot.cliLabel))
        row.reset = Normalizer.boundedDisplayText(resetText({resetsAt: snapshot.resetValue,
            resetDescription: snapshot.resetDescription}, false), 500)
        row.pace = paceSummaryPartsText(snapshot.paceParts)
        delete row.resetValue
        return row
    }

    // The popup pace line. Its run-out forecast counts down from the row's
    // observation like the panel, instead of repeating the receipt-time ETA.
    function usagePaceText(row) {
        if (!row || !row.pace) {
            return ""
        }
        return Array.isArray(row.paceParts)
            ? paceSummaryPartsText(PacePresentation.advancedParts(row.paceParts, row.paceObservedAtMs, panelClockMs))
            : row.pace
    }


    function providerCostSection(providerID, cost) {
        return providerCostDetails.costSection(providerID, cost)
    }

    function resetCreditsSection(providerID, resetCredits) {
        return providerCostDetails.resetSection(providerID, resetCredits)
    }

    function codexCreditLimitUsageRow(creditLimit) {
        return providerCostDetails.creditLimitRow(creditLimit)
    }

    function resetText(window, absolute) {
        return usageWindowText.resetText(window, panelClockMs, absolute)
    }

    function usageResetText(row) {
        row = PrivacyPresentation.quota(row, privacyMode, "")
        if (!row) {
            return ""
        }
        if (row.resetsAt || row.resetDescription) {
            return resetText({
                resetsAt: row.resetsAt || "",
                resetDescription: row.resetDescription || ""
            }, resetTimesShowAbsolute)
        }
        return String(row.reset || "")
    }

    function statusText(status) {
        // Status fields are CLI-controlled: read them without coercing objects,
        // whose missing toString would throw inside String().
        var indicator = Normalizer.safeScalarText(status.indicator)
        var description = Normalizer.safeScalarText(status.description).trim()
        if (indicator.length === 0 || indicator === "none") {
            return description
        }

        var labels = {
            "minor": i18n("Partial outage"),
            "major": i18n("Major outage"),
            "critical": i18n("Critical issue"),
            "maintenance": i18n("Maintenance"),
            "unknown": i18n("Status unknown")
        }
        var text = Guards.hasOwnKey(labels, indicator) ? labels[indicator] : indicator
        return description.length > 0 ? text + ": " + description : text
    }

    function statusBadgeColor(severity) {
        switch (String(severity || "")) {
        case "critical":
        case "major":
            return Kirigami.Theme.negativeTextColor
        case "minor":
        case "maintenance":
            return Kirigami.Theme.neutralTextColor
        case "unknown":
            return Kirigami.Theme.textColor
        default:
            return "transparent"
        }
    }

    function statusBadgeText(severity) {
        switch (String(severity || "")) {
        case "critical":
            return i18n("Critical")
        case "major":
            return i18n("Major")
        case "minor":
            return i18n("Issue")
        case "maintenance":
            return i18n("Maint.")
        case "unknown":
            return i18n("Unknown")
        default:
            return ""
        }
    }

    function primaryIncidentProvider() {
        var best = null
        var bestRank = 0
        for (var i = 0; i < providers.length; i++) {
            var item = providers[i]
            if (!item || item.statusKnown === false || item.hasIncident !== true) {
                continue
            }
            var rank = NotificationMemo.severityRank(item.statusSeverity)
            if (rank > bestRank) {
                best = item
                bestRank = rank
            }
        }
        return best
    }

    function quotaWarningMarkers(row) {
        if (!showQuotaWarningMarkers || !row || !row.hasPercent) {
            return []
        }
        return QuotaThresholds.markers(
            quotaWarningPercent,
            quotaCriticalPercent,
            usageBarsShowUsed)
    }

    // The thresholds used to surface only as two ticks on the provider detail
    // meter, so an almost exhausted window looked exactly like an idle one on
    // the panel and in the overview. Every meter fill reads its colour from
    // this one level; the provider accent stays in charge below the warning
    // step, and the same setting that hides the markers hides the colour.
    function quotaSeverity(row) {
        if (!showQuotaWarningMarkers || !row || !row.hasPercent) {
            return ""
        }
        return QuotaThresholds.level(row.usedPercent, quotaWarningPercent, quotaCriticalPercent)
    }

    function quotaMeterColor(row, accent) {
        var severity = quotaSeverity(row)
        return severity.length > 0 ? statusBadgeColor(severity) : accent
    }

    // Quota, pace, and reset memo state is threshold-derived and has to be
    // rebuilt whenever a setting changes. Provider status is not: a settings
    // change is not a status transition, so the status baseline survives the
    // reset. Dropping it would either re-announce an ongoing incident or, once
    // the first observation is silently primed, swallow an incident that starts
    // while the provider is still refreshing.
    function resetNotificationMemo() {
        notificationMemo = NotificationPlanner.transition(
            [], notificationMemo, ({ mode: "reset" })).nextMemo
        notificationsPrimed = false
        // Prime synchronously against the current snapshot so an incident that
        // starts between the reset and the next deferred pass cannot be
        // absorbed silently into the new baseline. The deferred call stays as
        // a coalesced follow-up for refreshes already in flight.
        processNotifications()
        Qt.callLater(processNotifications)
    }

    function notificationProviderRefreshPending(providerID) {
        var key = providerMapKey(providerID)
        return key.length > 0 && notificationRefreshPending[key] === true
    }

    function setNotificationProviderRefreshPending(providerID, pending) {
        var key = providerMapKey(providerID)
        if (key.length === 0) {
            return
        }
        var nextPending = copyObject(notificationRefreshPending)
        if (pending) {
            nextPending[key] = true
        } else {
            delete nextPending[key]
        }
        notificationRefreshPending = nextPending
    }

    function markNotificationProvidersFresh(items) {
        var nextPending = copyObject(notificationRefreshPending)
        for (var i = 0; i < items.length; i++) {
            var item = items[i]
            if (!item || (item.usageStale === true && item.statusKnown !== true)) {
                continue
            }
            var providerID = providerMapKey(item.provider)
            if (providerID.length === 0) {
                continue
            }
            var selectedAccount = selectedAccountForProvider(providerID)
            if (selectedAccount.length > 0 && accountKey(item) !== selectedAccount) {
                continue
            }
            // A failed account refresh can still carry fresh provider status.
            // The planner separately ignores missing quota evidence.
            delete nextPending[providerID]
        }
        notificationRefreshPending = nextPending
    }

    function notificationScopeKey(item) {
        if (!item) {
            return JSON.stringify(["", ""])
        }
        var providerID = providerMapKey(item.provider)
        var selectedAccount = selectedAccountForProvider(providerID)
        var currentAccount = selectedAccount.length > 0 ? selectedAccount : accountKey(item)
        return JSON.stringify([providerID, currentAccount])
    }

    function paceWarningActive(row) {
        return row && row.paceOnTop === false && Number(row.paceEtaSeconds) > 0
    }

    function paceSummaryText(pace) {
        return paceSummaryPartsText(PacePresentation.summaryParts(pace))
    }

    function paceSummaryPartsText(parts) {
        return usageWindowText.paceSummaryPartsText(parts)
    }

    function paceEtaText(seconds) {
        return usageWindowText.paceEtaText(seconds)
    }

    // Usage at or above this percent arms a row for reset detection; once armed,
    // dropping to or below the floor fires a single "limit reset" notification.
    // Mirrors the macOS weekly-limit reset detector, scoped to limits the user
    // was actually near so routine short-window resets stay quiet.
    readonly property int limitResetArmThreshold: 80
    readonly property int limitResetFloor: 5

    function quotaNotificationLevel(row) {
        if (!row || !row.hasPercent) {
            return ""
        }
        return QuotaThresholds.level(
            row.usedPercent,
            quotaWarningPercent,
            quotaCriticalPercent)
    }

    // QML resolves account identity, refresh freshness, configured thresholds,
    // and the rows to display. The pure planner receives only semantic
    // observations and returns ordered intents; it never sees i18n or effects.
    function notificationObservationRows(item) {
        if (item && item.usageStale === true) {
            return []
        }
        var sourceRows = item && Array.isArray(item.rows) ? item.rows : []
        var result = []
        for (var i = 0; i < sourceRows.length; i++) {
            var row = sourceRows[i]
            result.push({
                lane: row && row.lane ? String(row.lane) : "",
                label: row && row.label ? String(row.label) : "",
                resetsAt: row && row.resetsAt ? String(row.resetsAt) : "",
                hasPercent: row && row.hasPercent === true,
                usedPercent: row ? Number(row.usedPercent) : NaN,
                quotaLevel: quotaNotificationLevel(row),
                paceKnown: row && row.paceKnown === true,
                paceActive: paceWarningActive(row)
            })
        }
        return result
    }

    function notificationObservations() {
        var result = []
        for (var i = 0; i < providers.length; i++) {
            var item = providers[i]
            if (!item) {
                continue
            }
            var rows = notificationObservationRows(item)
            result.push({
                providerIndex: i,
                providerID: providerMapKey(item.provider),
                scopeID: notificationScopeKey(item),
                pending: NotificationPlanner.observationPending(
                    (item.usageStale === true && item.statusKnown !== true)
                        || notificationProviderRefreshPending(item.provider),
                    String(item.error || "").length > 0,
                    item.statusKnown === true,
                    rows.length),
                errorPresent: String(item.error || "").length > 0,
                usageStale: item.usageStale === true,
                statusKnown: item.statusKnown === true,
                statusActive: item.hasIncident === true
                    && String(item.statusSeverity || "").length > 0
                    && String(item.status || "").length > 0,
                statusSeverity: String(item.statusSeverity || ""),
                statusIncidentKey: String(item.statusIncidentKey || ""),
                rows: rows
            })
        }
        return result
    }

    function notificationPlannerOptions(mode) {
        return {
            mode: mode,
            statusEnabled: includeStatus && notifyStatusIncidents,
            quotaEnabled: notifyQuotaWarnings,
            paceEnabled: notifyPredictivePaceWarnings,
            resetEnabled: notifyLimitResets,
            resetArmThreshold: limitResetArmThreshold,
            resetFloor: limitResetFloor
        }
    }

    function dispatchNotificationIntents(intents, observations) {
        for (var i = 0; i < intents.length; i++) {
            var intent = intents[i]
            var observation = observations[intent.observationIndex]
            var item = observation ? providers[observation.providerIndex] : null
            if (!item) continue
            var rows = Array.isArray(item.rows) ? item.rows : []
            var row = rows[intent.rowIndex]
            var resetLine = row && intent.kind === "quota" ? resetLabel(usageResetText(row)) : ""
            var paceEta = row && intent.kind === "pace" ? paceEtaText(row.paceEtaSeconds) : ""
            var message = providerNotificationText.message(intent, item, row, resetLine, paceEta)
            if (message) sendPlasmaNotification(message.title, message.body, message.urgency)
        }
    }

    function processNotifications() {
        if (!enableNotifications || providers.length === 0) {
            return
        }
        var observations = notificationObservations()
        var mode = notificationsPrimed ? "observe" : "prime"
        var result = NotificationPlanner.transition(
            observations,
            notificationMemo,
            notificationPlannerOptions(mode))
        // Commit the full transition before running any external effect. A
        // re-entrant refresh cannot observe the old baseline and notify twice.
        notificationMemo = result.nextMemo
        notificationsPrimed = true
        dispatchNotificationIntents(result.intents, observations)
    }

    function sendPlasmaNotification(title, body, urgency, actionLabel) {
        return updateNotifications.send(title, body, urgency, actionLabel)
    }

    // Settings request manual widget updates through this runtime key, and the
    // applet runs them, so closing the dialog cannot cut an install short.
    readonly property string widgetUpdateRequest: Plasmoid.configuration.widgetUpdateRequest || ""
    onWidgetUpdateRequestChanged: serviceWidgetUpdateRequest()

    // Plasma exposes KPluginMetaData at runtime without a declarative QML type.
    readonly property var appletContext: Plasmoid
    readonly property string installedWidgetVersion: appletContext && appletContext.metaData
        ? String(appletContext.metaData.version || "") : ""

    // A found release stays offered only while it is newer than this widget,
    // so upgrading another way does not leave an Install button for it.
    function restoredWidgetUpdateVersion() {
        return UpdateLogic.restoredAvailableVersion(
            Plasmoid.configuration.widgetUpdateAvailableVersion || "", installedWidgetVersion)
    }

    function forgetInstalledWidgetUpdate() {
        var restored = restoredWidgetUpdateVersion()
        if (restored !== (Plasmoid.configuration.widgetUpdateAvailableVersion || "")) {
            Plasmoid.configuration.widgetUpdateAvailableVersion = restored
        }
    }

    function serviceWidgetUpdateRequest() {
        var request = widgetUpdateRequest
        if (widgetUpdater.busy || request.length === 0) {
            return
        }
        if (request === "check" || request === "install") {
            // Start first: busy then keeps the marker write below from re-entering.
            widgetUpdater.runNow(request === "install")
            if (widgetUpdater.busy) {
                Plasmoid.configuration.widgetUpdateRequest = "running:" + request
                return
            }
        }
        // A finished run, a stale marker from a previous session, or junk.
        Plasmoid.configuration.widgetUpdateRequest = ""
    }

    function notifyAvailableUpdate(version, url, releaseUrl) {
        updateNotifications.notifyAvailableUpdate(version, url, releaseUrl)
    }

    function notifyInstalledUpdate(version) {
        updateNotifications.notifyInstalledUpdate(version)
    }

    function planText(providerID, method) {
        if (providerKey(providerID) === "codex" && method.length > 0) {
            return capitalize(method)
        }
        return ""
    }

    function providerKey(value) {
        return ProviderIdentity.resolveProviderKey(value)
    }

    function providerCliArgument(value) {
        return ProviderIdentity.providerCliArgument(value)
    }

    function providerDisplayTitle(value) {
        return providerTitle(value, "", privacyMode)
    }

    function providerTitle(value, displayName, privateTitle) {
        var key = providerKey(value)
        // Optional display names are CLI-controlled and may carry structured
        // values: their primitive conversion throws and would discard the
        // whole provider snapshot. Only truthy scalars reach String();
        // anything else degrades to the bundled fallback, keeping the quota.
        var rawDisplay = displayName || ""
        if (typeof rawDisplay !== "string" && typeof rawDisplay !== "number" && typeof rawDisplay !== "boolean") {
            rawDisplay = ""
        }
        var preferred = privateTitle === true ? "" : String(rawDisplay).trim()
        if (preferred.length > 0) {
            return preferred
        }
        return providerNames.titleForKey(key, privateTitle === true ? i18n("Provider") : "")
    }

    function providerIconSource(value) {
        var fileName = ProviderIdentity.providerIconFileName(value)
        if (fileName.length === 0) {
            return "view-statistics"
        }
        return Qt.resolvedUrl("../icons/providers/" + fileName)
    }

    function providerIconIsMask(value) {
        return true
    }

    // Whether the rendered icon can stand in for the provider's name. Bundled
    // icons and brand colors cover the same providers, so a provider outside
    // that set falls back to one generic icon in the theme highlight and is
    // indistinguishable from every other provider outside it.
    function providerIconIdentifies(value) {
        return ProviderIdentity.providerBrandColorChannels(value).length === 3
    }

    function providerColor(value) {
        var channels = ProviderIdentity.providerBrandColorChannels(value)
        if (channels.length !== 3) {
            return Kirigami.Theme.highlightColor
        }
        return Qt.rgba(channels[0], channels[1], channels[2], 1)
    }

    function providerDashboardUrl(providerID) {
        return ProviderIdentity.providerDashboardUrl(providerID)
    }

    function providerDocsUrl(providerID) {
        return ProviderIdentity.providerDocsUrl(providerID)
    }

    function providerLoginUrl(providerID) {
        return ProviderIdentity.providerLoginUrl(providerID)
    }

    function providerStatusUrl(providerID) {
        return ProviderIdentity.providerStatusUrl(providerID)
    }

    function safeStatusUrl(providerID, url) {
        return Normalizer.safeStatusUrl(providerStatusUrl(providerID), url)
    }

    function providerChangelogUrl(providerID) {
        switch (providerKey(providerID)) {
        case "codex":
            return "https://github.com/openai/codex/releases"
        case "claude":
            return "https://github.com/anthropics/claude-code/releases"
        case "gemini":
            return "https://github.com/google-gemini/gemini-cli/releases"
        case "grok":
            return "https://x.ai/news"
        default:
            return ""
        }
    }

    function actionRows(item) {
        if (!item) {
            return []
        }

        // This menu uses raw provider capabilities and account presence only.
        // Titles are local literals; never render identity or provider prose here.
        var rows = []
        rows.push({
            title: accountLoadingForProvider(item.provider) ? i18n("Loading accounts…") : i18n("Accounts…"),
            icon: "user-identity",
            action: "accounts",
            enabled: !accountLoadingForProvider(item.provider)
        })

        var accountAction = providerAccountAction(item)
        if (accountAction) {
            rows.push(accountAction)
        }

        if (item.dashboardUrl && item.dashboardUrl.length > 0) {
            rows.push({ title: i18n("Usage Dashboard"), icon: "view-statistics", action: "dashboard", enabled: true })
        }
        if (safeStatusUrl(item.provider, item.statusUrl).length > 0) {
            rows.push({ title: i18n("Status Page"), icon: "network-connect", action: "status", enabled: true })
        }
        if (showProviderChangelogs && item.changelogUrl && item.changelogUrl.length > 0) {
            rows.push({ title: i18n("Changelog"), icon: "view-list-details", action: "changelog", enabled: true })
        }
        var docsUrl = providerDocsUrl(item.provider)
        if (docsUrl.length > 0) {
            rows.push({ title: i18n("Docs"), icon: "help-contents", action: "docs", url: docsUrl, enabled: true })
        }

        rows.push({ title: i18n("Refresh"), icon: "view-refresh", action: "refresh", enabled: true, separatorBefore: true })
        rows.push({ title: i18n("Settings…"), icon: "configure", action: "settings", enabled: true })
        rows.push({ title: i18n("About CodexBar"), icon: "help-about", action: "about", enabled: true })
        return rows
    }

    function providerAccountAction(item) {
        var title = item.account && item.account.length > 0 ? i18n("Switch Account…") : i18n("Add Account…")
        var loginUrl = providerLoginUrl(item.provider)
        switch (providerKey(item.provider)) {
        case "devin":
            return { title: i18n("Open Devin…"), icon: "internet-services", action: "account-url", url: "https://app.devin.ai/settings/usage", enabled: true }
        case "factory":
            return { title: i18n("Open Droid in Browser…"), icon: "internet-services", action: "account-url", url: "https://app.factory.ai", enabled: true }
        case "manus":
            return { title: title, icon: "internet-services", action: "account-url", url: "https://manus.im", enabled: true }
        case "mimo":
            return { title: title, icon: "internet-services", action: "account-url", url: "https://platform.xiaomimimo.com/api/v1/genLoginUrl?currentPath=%2F%23%2Fconsole%2Fbalance", enabled: true }
        case "perplexity":
            return { title: title, icon: "internet-services", action: "account-url", url: "https://www.perplexity.ai/", enabled: true }
        default:
            return loginUrl.length > 0
                ? { title: title, icon: "internet-services", action: "account-url", url: loginUrl, enabled: true }
                : null
        }
    }

    function aiInsightsLanguageTag() {
        return AiInsights.languageTag(i18nc(
            "BCP 47 language tag of this translation, such as it or pt-BR. AI Insights are written in this language.", "en"))
    }

    function generateAiInsight() {
        aiInsightsController.generate()
    }

    function aiInsightsProviderName(provider) {
        return aiInsightsMessages.providerName(provider)
    }

    function aiInsightsErrorText(reason) {
        return aiInsightsMessages.errorText(reason, aiInsightsController.requestContext.provider)
    }

    function performAction(actionRow) {
        var actionID = actionRow && actionRow.action ? actionRow.action : actionRow
        var item = selectedProviderData
        if (actionID === "dashboard" && item) {
            Qt.openUrlExternally(item.dashboardUrl)
        } else if (actionID === "status" && item) {
            Qt.openUrlExternally(safeStatusUrl(item.provider, item.statusUrl))
        } else if (actionID === "changelog" && item) {
            Qt.openUrlExternally(item.changelogUrl)
        } else if (actionID === "docs" && actionRow && actionRow.url) {
            Qt.openUrlExternally(actionRow.url)
        } else if (actionID === "accounts" && item) {
            root.loadAccounts(item.provider)
        } else if (actionID === "account-url" && actionRow && actionRow.url) {
            Qt.openUrlExternally(actionRow.url)
        } else if (actionID === "refresh") {
            root.refreshNow(true)
        } else if (actionID === "about") {
            Qt.openUrlExternally("https://github.com/steipete/CodexBar")
        } else if (actionID === "settings") {
            var action = Plasmoid.internalAction("configure")
            if (action) {
                action.trigger()
            }
        }
    }

    function withAlpha(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha)
    }

    function canvasColor(color, alpha) {
        var opacity = alpha === undefined ? color.a : alpha
        return "rgba("
            + Math.round(color.r * 255) + ", "
            + Math.round(color.g * 255) + ", "
            + Math.round(color.b * 255) + ", "
            + opacity + ")"
    }

    function contrastTextColor(color) {
        var luminance = (0.2126 * color.r) + (0.7152 * color.g) + (0.0722 * color.b)
        return luminance > 0.62 ? Qt.rgba(0.08, 0.08, 0.1, 1) : Qt.rgba(1, 1, 1, 1)
    }

    function readableAccentColor(accent, background) {
        var surface = background || Kirigami.Theme.backgroundColor
        return ThemeContrast.readableAccentColor(
            accent,
            surface,
            Kirigami.Theme.textColor)
    }

    function providerReadableColor(value, background) {
        return readableAccentColor(
            providerColor(value),
            background || Kirigami.Theme.backgroundColor)
    }

    function copyObject(item) {
        return Guards.copyObject(item)
    }

    function capitalize(value) {
        var text = String(value || "")
        if (text.length === 0) {
            return ""
        }
        return text.charAt(0).toUpperCase() + text.slice(1)
    }

    // Four- and five-figure totals are unreadable as a bare digit run, and
    // Number.toLocaleString with 'f' localizes the decimal mark without adding
    // group separators, so the grouping is applied here.
    function groupedDecimalString(value, digits) {
        return CostPresentation.groupedDecimalString(costNumberFormat, value, digits)
    }

    function amountString(value, currency) {
        return CostPresentation.amountString(costNumberFormat, value, currency)
    }

    // Same figures as costLine without the window label, for surfaces that
    // already state the range once (the Usage & Spend range selector).
    function qualifiedCostValue(value, valueMode) {
        return costText.qualifiedCostValue(value, valueMode)
    }

    function costValueLine(cost, tokens, currency, valueMode) {
        return costText.costValueLine(cost, tokens, currency, valueMode)
    }

    function costLine(label, cost, tokens, currency, valueMode) {
        return costText.costLine(label, cost, tokens, currency, valueMode)
    }

    function tokenCountString(tokens) {
        return CostPresentation.tokenCountString(tokens, costNumberFormat)
    }

    function usageCountText(value, unit) {
        return costText.usageCountText(value, unit)
    }

    function tokenCostHint(providerID) {
        return costText.tokenCostHint(providerID)
    }

    function switcherCandidateRows(item) {
        return PanelDisplay.candidateRows(item ? item.rows : null,
            item ? providerKey(item.provider) : "", item ? item.providerCost : null,
            i18n("Included plan"))
    }

    function panelDisplayRow(item, mode) {
        return PanelDisplay.rowForMode(switcherCandidateRows(item), mode, panelQuotaLane)
    }

    function panelMeterRows(item) {
        return PanelDisplay.meterRows(switcherCandidateRows(item), panelQuotaLane)
    }

    function panelMeterDescription(item) {
        var description = panelMeterRows(item).map(function(row) {
            var text = i18n("%1: %2% %3", row.label, Math.round(displayPercent(row)),
                usageBarsShowUsed ? i18n("used") : i18n("left"))
            var reset = resetTextForRow(row)
            return reset.length > 0 ? i18n("%1 - %2", text, reset) : text
        }).join(". ")
        if (!item || item.usageStale !== true) {
            return description
        }
        var lastKnown = lastGoodUsageText(item)
        return description.length > 0 ? i18n("%1 - %2", description, lastKnown) : lastKnown
    }

    function switcherMetricRow(item) {
        // Popup tabs retain their automatic quota independently of panel settings.
        return PanelDisplay.rowForMode(switcherCandidateRows(item), "percent")
    }

    function switcherPercent(item) {
        var row = switcherMetricRow(item)
        return row ? displayPercent(row) : -1
    }

    // A popup tab shows its quota only as an underline and its failure only
    // by dimming, so screen readers get both as text.
    function switcherDescription(item) {
        if (!item) {
            return ""
        }
        var parts = []
        var row = switcherMetricRow(item)
        if (row && row.hasPercent) {
            var text = i18n("%1: %2% %3", row.label, Math.round(displayPercent(row)), percentSuffix())
            var reset = resetTextForRow(row)
            parts.push(reset.length > 0 ? i18n("%1 - %2", text, reset) : text)
        }
        if (item.usageStale === true) {
            parts.push(lastGoodUsageText(item))
        }
        if (item.error && item.error.length > 0) {
            parts.push(item.error)
        }
        return parts.join(". ")
    }

    // Eligibility, the stored selection, and the visible limit all live in
    // OverviewProviders, so the settings checkboxes and the rendered rows
    // resolve the same canonical provider IDs.
    function overviewProviders() {
        return OverviewProviders.visibleItems(providers, overviewProviderIDsRaw)
    }

    function providerIndex(item) {
        return item ? providerIndexForID(item.provider) : -1
    }

    function providerIndexForID(providerID) {
        var id = String(providerID || "")
        if (id.length === 0 || !providers) {
            return -1
        }
        for (var i = 0; i < providers.length; i++) {
            if (providers[i] && providers[i].provider === id) {
                return i
            }
        }
        return -1
    }

    function openProviderFromPanel(providerID) {
        var index = providerIndexForID(providerID)
        if (index < 0) {
            return false
        }
        selectedProviderID = providers[index].provider
        selectionInitialized = true
        expanded = true
        return true
    }

    function providerPlaceholderText(item) {
        return OverviewProviders.placeholderText(item)
    }

    function displayPercent(row) {
        if (!row || !row.hasPercent) {
            return 0
        }
        return usageBarsShowUsed ? row.usedPercent : row.leftPercent
    }

    function paceMarkerPercent(row) {
        if (!row || row.pacePercent < 0) {
            return -1
        }
        return usageBarsShowUsed ? row.pacePercent : clamp(100 - row.pacePercent, 0, 100)
    }

    function percentSuffix() {
        return usageBarsShowUsed ? i18n("used") : i18n("left")
    }

    function resetLabel(value) {
        return usageWindowText.resetLabel(value)
    }

    function providerCountText(count) {
        var total = Math.max(0, Math.round(Number(count) || 0))
        return i18np("%1 provider", "%1 providers", total)
    }

    function clamp(value, minimum, maximum) {
        return Normalizer.clamp(value, minimum, maximum)
    }

    function selectedCompactProvider() {
        if (providers.length === 0) {
            return null
        }
        var panelItems = panelProviderItems()
        var selected = selectedProviderIndex >= 0 ? providers[selectedProviderIndex] : null
        return PopupSelection.compactPanelProvider(
            autoSelectProvider, selected, panelItems,
            autoSelectedProviderIndex(panelItems))
    }

    function globalViewAvailability() {
        return {
            overview: overviewAvailable,
            spend: spendAvailable,
            sessions: sessionsAvailable
        }
    }

    function selectGlobalView(viewID) {
        var candidate = String(viewID || "")
        if (!PopupSelection.globalViewIsAvailable(candidate, globalViewAvailability())) {
            return
        }

        selectedGlobalView = candidate
        selectedProviderID = ""
        selectionInitialized = true
        if (candidate === "spend") {
            refreshSpendIfStale()
        }
    }

    function updateSelectedProvider() {
        var firstProviderID = providers && providers.length > 0
            ? providers[0].provider
            : ""
        var automaticProviderID = firstProviderID.length > 0
            ? providers[autoSelectedProviderIndex(providers)].provider
            : ""
        var next = PopupSelection.reconcile({
            providerID: selectedProviderID,
            globalView: selectedGlobalView,
            initialized: selectionInitialized
        }, {
            autoSelect: autoSelectProvider,
            currentProviderExists: selectedProviderIndex >= 0,
            firstProviderID: firstProviderID,
            automaticProviderID: automaticProviderID,
            globalViews: globalViewAvailability()
        })
        selectedProviderID = next.providerID
        selectedGlobalView = next.globalView
        selectionInitialized = next.initialized
    }

    function reconcileGlobalViewAvailability() {
        if (PopupSelection.globalSelectionNeedsReconciliation({
            providerID: selectedProviderID,
            globalView: selectedGlobalView,
            initialized: selectionInitialized
        }, globalViewAvailability())) {
            updateSelectedProvider()
        }
    }

    // Usage and incident severity decide the automatic selection in
    // ProviderAutoSelect; the roster it ranks is the panel-filtered list for
    // the panel and the full roster for the popup.
    function autoSelectedProviderIndex(items) {
        return ProviderAutoSelect.bestIndex(Array.isArray(items) ? items : providers)
    }

    // The panel-only provider selection. The popup, notifications, and every
    // other surface keep the full roster; only compact rendering narrows here.
    function panelProviderItems() {
        return PanelProviders.filteredItems(providers, panelProviderIDsRaw)
    }

    function compactProviders() {
        if (!providers || Plasmoid.configuration.showMultiProviderInPanel === false) {
            return []
        }

        var result = []
        var panelItems = panelProviderItems()
        for (var i = 0; i < panelItems.length && result.length < PanelProviders.maximumSelectableProviders; i++) {
            var rows = panelMeterRows(panelItems[i])
            if (PanelRules.matchesAny(panelVisibilityRules.meters, rows, panelClockMs)) {
                result.push(providerPresentation(panelItems[i]))
            }
        }
        return result
    }

    // The panel label as separable segments. The compact renderer surrenders
    // whole segments when the meter row leaves it too little room, so it needs
    // them apart; every other caller joins them back through compactText().
    function compactTextSegments() {
        var item = providerPresentation(selectedCompactProvider())
        var row = panelDisplayRow(item, menuBarDisplayMode)
        return panelText.segments(item,
            PanelRules.matches(panelVisibilityRules.text, row, panelClockMs),
            PanelProviders.selectionActive(panelProviderIDsRaw),
            item ? menuBarDisplayText(item) : "",
            item ? providerIconIdentifies(item.provider) : false)
    }

    function compactText() {
        return panelText.fullText(compactTextSegments())
    }

    function setHoveredPanelProvider(providerID) {
        hoveredPanelProviderID = String(providerID || "")
    }

    function clearHoveredPanelProvider(providerID) {
        var id = String(providerID || "")
        if (hoveredPanelProviderID === id) {
            hoveredPanelProviderID = ""
        }
    }

    function hoveredPanelProvider() {
        var id = String(hoveredPanelProviderID || "")
        if (id.length === 0 || !providers) {
            return null
        }
        // Visibility rules can filter a hovered meter out of the rendered
        // compactProviders() while its provider stays in providers, and its
        // destroyed MouseArea delivers no reliable hover-exit for cleanup.
        // Narrow the tooltip only while the meter is actually rendered.
        var rendered = compactProviders().some(function(meter) {
            return meter && meter.provider === id
        })
        if (!rendered) {
            return null
        }
        for (var i = 0; i < providers.length; i++) {
            if (providers[i] && providers[i].provider === id) {
                return providers[i]
            }
        }
        return null
    }

    function panelProviderToolTipText(item) {
        var presented = providerPresentation(item)
        return panelText.providerToolTipText(presented, panelMeterDescription(presented))
    }

    function panelToolTipText() {
        var hovered = hoveredPanelProvider()
        var hoveredLine = hovered ? panelProviderToolTipText(hovered) : ""
        if (hoveredLine.length > 0) {
            return hoveredLine
        }
        var lines = []
        var roster = panelProviderItems()
        for (var i = 0; i < roster.length && lines.length < 6; i++) {
            var line = panelProviderToolTipText(roster[i])
            if (line.length > 0) {
                lines.push(line)
            }
        }
        return panelText.toolTipText(lines,
            privateErrorText(Normalizer.boundedDisplayText(errorText, 500)))
    }

    function menuBarDisplayText(item) {
        if (!item) {
            return ""
        }
        var mode = String(menuBarDisplayMode || "percent")
        var row = panelDisplayRow(item, mode)
        return panelText.displayText(row, mode,
            mode === "resetTime" ? resetTextForRow(row) : "",
            mode === "runOut" ? runOutTextForRow(row) : "")
    }

    // Duration-only forecast token. It stays empty unless the CLI actually
    // predicts exhaustion before the reset, so the panel never shows a
    // countdown the pace data does not support.
    // Account options retain their own receipt time across later refreshes.
    function runOutTextForRow(row) {
        if (!paceWarningActive(row)) {
            return ""
        }
        return paceEtaText(PanelDisplay.remainingSeconds(
            row.paceEtaSeconds, row.paceObservedAtMs, panelClockMs))
    }

    function resetTextForRow(row) {
        var reset = usageResetText(row)
        if (reset.length === 0) {
            return ""
        }
        return resetLabel(reset)
    }

    // Credit balances are plain counts, so they share the popup's grouped,
    // locale-aware figure formatting instead of printing a bare digit run with
    // a hardcoded decimal mark. A whole balance keeps no fractional part, so a
    // depleted account reads as "0" rather than "0.0".
    function formatNumber(value) {
        return CostPresentation.formatCount(costNumberFormat, value)
    }

    Timer {
        id: panelClockTimer

        interval: root.panelClockIntervalMs
        repeat: true
        running: root.providers.length > 0
        triggeredOnStart: false
        onTriggered: {
            root.panelClockMs = Date.now()
            root.expireStaleUsage(root.panelClockMs)
        }
    }

    Components.CostText {
        id: costText
        numberFormat: root.costNumberFormat
    }

    Components.UsageWindowText {
        id: usageWindowText
        dateLabels: timeLabels
    }

    Components.ProviderNotificationText {
        id: providerNotificationText
    }

    Components.ProviderCostDetails {
        id: providerCostDetails

        numberFormat: root.costNumberFormat
    }

    Components.PanelText {
        id: panelText

        loading: root.loading
        usageBarsShowUsed: root.usageBarsShowUsed
        showProvider: Plasmoid.configuration.showProviderInPanel
        showPercent: Plasmoid.configuration.showPercentInPanel
        showCredits: Plasmoid.configuration.showCreditsInPanel
        numberFormat: root.costNumberFormat
    }

    Components.ProviderNames {
        id: providerNames
    }

    Components.RateWindowLabels {
        id: rateWindowLabels
    }

    Components.TimeLabels {
        id: timeLabels
    }

    Components.AiInsightsMessages {
        id: aiInsightsMessages
    }

    Controllers.ProviderConfigWatcher {
        id: providerConfigWatcher

        active: root.usageLifecycleInitialized
        onStampObserved: function(stamp, initial) {
            root.handleProviderConfigObservation(stamp, initial)
        }
    }

    Controllers.UpdateNotificationsController {
        id: updateNotifications

        configuration: Plasmoid.configuration
        enableNotifications: root.enableNotifications
        privacyMode: root.privacyMode
        onReleasePageRequested: function(url) {
            Qt.openUrlExternally(url)
        }
    }

    Controllers.UsageController {
        id: usageController

        commandPath: root.commandPath
        provider: root.provider
        sourceMode: root.source
        includeStatus: root.includeStatus
        selectedAccounts: root.selectedAccounts
        providerConfigRevision: root.providerConfigRevision
        providerConfigStamp: root.providerConfigStamp
        providerOrderRaw: root.providerOrderRaw
        refreshIntervalSec: root.refreshIntervalSec
        refreshOnOpen: root.refreshOnOpen
        popupVisible: root.expanded
        onSnapshotReceived: function(items) {
            root.commitUsageSnapshot(items.map(function(item) { return root.presentProviderSnapshot(item) }))
            root.applyTokenCosts()
        }
        onFailed: function(message) { root.failUsageRefresh(message) }
        onEmptyRoster: root.invalidateUsageData()
    }

    Controllers.AccountsController {
        id: accountsController

        commandPath: root.commandPath
        sourceMode: root.source
        includeStatus: root.includeStatus
    }

    Controllers.CostController {
        id: costController

        commandPath: root.commandPath
        provider: root.provider
        historyDays: root.costHistoryDays
        historyPeriod: root.costHistoryPeriod
        costUsageEnabled: root.costUsageEnabled
        active: root.spendSelected && root.expanded
    }

    Controllers.SessionsController {
        id: sessionsController

        commandPath: root.commandPath
        refreshIntervalSec: root.refreshIntervalSec
        active: root.expanded && root.sessionsSelected
    }

    Controllers.AiInsightsController {
        id: aiInsightsController

        insightsEnabled: root.aiInsightsEnabled
        provider: Plasmoid.configuration.aiInsightsProvider || "ollama"
        model: Plasmoid.configuration.aiInsightsModel || ""
        endpoint: Plasmoid.configuration.aiInsightsOllamaEndpoint || ""
        zdr: Plasmoid.configuration.aiInsightsOpenRouterZdr !== false
        language: root.aiInsightsLanguage
        intervalHours: AiInsights.intervalHours(Plasmoid.configuration.aiInsightsIntervalHours)
        snapshotText: root.aiInsightsSnapshot.text
        snapshotId: root.aiInsightsSnapshot.id
        cacheText: root.aiInsightsEnabled ? (Plasmoid.configuration.aiInsightsCache || "") : ""
        lastAttempt: Plasmoid.configuration.aiInsightsLastAttempt || ""
        rateLimit: Plasmoid.configuration.aiInsightsRateLimit || ""
        onAttemptStarted: function(timestamp) {
            Plasmoid.configuration.aiInsightsLastAttempt = timestamp
        }
        onRateLimitStored: function(text) {
            Plasmoid.configuration.aiInsightsRateLimit = text
        }
        onGenerated: function(text) {
            Plasmoid.configuration.aiInsightsCache = text
        }
    }

    Controllers.ManagedCliController {
        commandPath: root.commandPath
        automaticUpdates: Plasmoid.configuration.cliAutomaticUpdates === true
        onChanged: root.refreshNow(true)
    }

    Controllers.CliUpdateController {
        commandPath: root.commandPath
        automaticChecks: Plasmoid.configuration.cliUpdateChecksEnabled === true
        lastCheck: Plasmoid.configuration.cliUpdateLastCheck || ""
        onCheckedRelease: function(timestamp) {
            Plasmoid.configuration.cliUpdateLastCheck = timestamp
        }
        onUpdateAvailable: function(version, releaseUrl) {
            updateNotifications.notifyAvailableCliUpdate(version, releaseUrl)
        }
    }

    Controllers.WidgetUpdateController {
        id: widgetUpdater
        updateChecksEnabled: Plasmoid.configuration.updateChecksEnabled !== false
        autoUpdateEnabled: Plasmoid.configuration.autoUpdateEnabled === true
        autoUpdateIntervalHours: isFinite(Number(Plasmoid.configuration.autoUpdateIntervalHours))
            ? Math.max(1, Math.min(168, Number(Plasmoid.configuration.autoUpdateIntervalHours))) : 24
        autoUpdateLastCheck: Plasmoid.configuration.autoUpdateLastCheck || ""
        initialAvailableVersion: root.restoredWidgetUpdateVersion()

        onStatusRecorded: function(statusText, errorText, availableVersion) {
            Plasmoid.configuration.widgetUpdateLastStatus = statusText
            Plasmoid.configuration.widgetUpdateLastError = errorText
            Plasmoid.configuration.widgetUpdateAvailableVersion = availableVersion
        }
        // Deferred: busy drops inside the controller's own completion handling.
        onBusyChanged: if (!busy) Qt.callLater(root.serviceWidgetUpdateRequest)
        onCheckSucceeded: function(timestamp) {
            Plasmoid.configuration.autoUpdateLastCheck = timestamp
        }
        onUpdateAvailable: function(version, assetUrl, releaseUrl) {
            root.notifyAvailableUpdate(version, assetUrl, releaseUrl)
        }
        onUpdateInstalled: function(version) {
            root.notifyInstalledUpdate(version)
        }
    }

    compactRepresentation: Components.CompactRepresentation {
        applet: root
    }

    fullRepresentation: Components.FullRepresentation {
        applet: root
    }
}
