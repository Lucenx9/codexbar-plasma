.pragma library
.import "ProviderNormalizer.js" as Normalizer

// A normalized semantic snapshot plus QML-localized/enriched fields. Never copy
// arbitrary input fields into the view model or the persisted quota contract.
function presented(snapshot, display) {
    var rows = Array.from(display.rows)
    return {
        provider: snapshot.provider,
        title: Normalizer.boundedDisplayText(display.title, 120),
        source: snapshot.source,
        dataConfidence: snapshot.dataConfidence,
        version: snapshot.version,
        account: snapshot.account,
        organization: snapshot.organization,
        loginMethod: snapshot.loginMethod,
        accountKey: snapshot.accountKey,
        rows: rows,
        primaryRow: rows.length > 0 && rows[0].lane === "primary" ? rows[0] : null,
        // Nested signal values can be Qt sequences; the pure visibility
        // filters consume JavaScript arrays, as do freshly parsed snapshots.
        providerDetails: Array.from(snapshot.providerDetails),
        subscriptionDates: Array.from(snapshot.subscriptionDates),
        usageDashboard: display.usageDashboard,
        providerCost: display.providerCost,
        resetCredits: display.resetCredits,
        tokenCost: display.tokenCost,
        codexCreditLimit: snapshot.codexCreditLimit,
        planText: Normalizer.boundedDisplayText(display.planText, 120),
        dashboardUrl: display.dashboardUrl,
        statusUrl: display.statusUrl,
        changelogUrl: display.changelogUrl,
        credits: snapshot.credits,
        status: Normalizer.boundedDisplayText(display.status, 500),
        statusKnown: snapshot.statusRecord !== null,
        statusSeverity: snapshot.statusSeverity,
        statusIncidentKey: snapshot.statusIncidentKey,
        hasIncident: snapshot.statusSeverity.length > 0,
        error: display.error,
        placeholder: display.placeholder,
        usageReceivedAtMs: snapshot.usageReceivedAtMs,
        updatedAt: snapshot.updatedAt
    }
}
