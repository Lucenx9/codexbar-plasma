.pragma library
.import "Guards.js" as Guards
.import "ProviderIdentity.js" as ProviderIdentity
.import "SafeText.js" as SafeText

// Pure normalization of untrusted `codexbar` CLI payloads.
//
// `main.qml` owns the two halves that used to share the `parse*` prefix: the
// process lifecycle, the root properties, the error text, and the loading flag
// stay there, while the raw-JSON-to-validated-structure half lives here. The
// split is mechanical: nothing in this file may touch `root`, a QML property,
// `Qt`, `Kirigami`, or `i18n`.
//
// The `i18n` exclusion is not a style rule. This file is in the gettext
// extraction glob, so a user-facing string here would be extracted untranslated.
// That is why the label of a rate window, the reset description, and the cost
// section titles stay in `main.qml` and only the numbers, the bounds, and the
// shape checks moved: `rateWindowMetrics` returns clamped percentages and the
// caller supplies the words.
//
// Every bound below is a delegate/allocation budget applied to attacker- or
// bug-influenced array lengths, so a malformed payload truncates instead of
// hanging the popup. They are asserted by `scripts/test_security_regressions.sh`
// and exercised by `tests/tst_provider_normalizer.qml`.

var maximumProviderSnapshots = 256
var maximumAccountSnapshots = 128
var maximumCostSnapshots = 256
var maximumExtraRateWindows = 24
var maximumSessions = 128
var maximumCostHistoryPoints = 365
var maximumCostHistoryScanItems = 2048
var maximumModelBreakdownsPerDay = 128
// Coverage counters are metadata, not allocation sizes, but bounding them keeps
// later aggregation inside an exact and intentionally small numeric domain.
var maximumCostCoverageCount = 1000000000

// Longest CLI-controlled pace ETA we will keep, in seconds.
var maximumPaceEtaSeconds = 31536000

function hasOwnKey(item, key) {
    return Guards.hasOwnKey(item, key)
}

function isUnsafeObjectKey(key) {
    return Guards.isUnsafeObjectKey(key)
}

// A CLI record is a plain object. Arrays and null are rejected because every
// caller indexes named fields on the result.
function isCliRecord(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
}

function copyObject(item) {
    return Guards.copyObject(item)
}

function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, value))
}

function strictFiniteNumber(value) {
    var numericType = typeof value === "number"
        || (typeof value === "string" && value.trim().length > 0)
    if (!numericType) {
        return Number.NaN
    }
    var numeric = Number(value)
    return isFinite(numeric) ? numeric : Number.NaN
}

function firstStrictFiniteNumber(preferred, fallback) {
    var numeric = strictFiniteNumber(preferred)
    return isFinite(numeric) ? numeric : strictFiniteNumber(fallback)
}

function boundedDisplayText(value, maximumLength) {
    var limit = Number(maximumLength)
    if (!isFinite(limit) || limit <= 0) {
        limit = 500
    }
    limit = Math.min(2000, Math.floor(limit))
    return SafeText.cliMessage(value, limit)
}

// The canonical map key for a provider: CLI aliases resolved, then screened for
// keys that would reach Object.prototype or smuggle control characters.
function providerSnapshotKey(providerID) {
    return ProviderIdentity.providerMapKey(ProviderIdentity.resolveProviderKey(providerID))
}

// "" for anything that cannot name a provider, so callers skip the entry rather
// than inventing an id from a non-string or an oversized payload field.
function normalizedProviderID(value) {
    if (typeof value !== "string") {
        return ""
    }
    var trimmed = value.trim()
    if (trimmed.length === 0 || trimmed.length > ProviderIdentity.maximumProviderIDLength) {
        return ""
    }
    return providerSnapshotKey(trimmed)
}

// `config providers` output reduced to the enabled provider ids plus every
// display name it carried. A disabled provider still contributes its name,
// because the popup labels providers it learns about from a later usage payload.
function normalizeProviderConfigEntries(payload) {
    var providerIDs = []
    var displayNames = ({})
    var seenProviderIDs = ({})
    var items = Array.isArray(payload) ? payload : [payload]
    var itemLimit = Math.min(items.length, maximumProviderSnapshots)
    for (var i = 0; i < itemLimit; i++) {
        if (isCliRecord(items[i]) && items[i].provider) {
            var providerID = normalizedProviderID(items[i].provider)
            if (providerID.length === 0) {
                continue
            }
            var displayName = boundedDisplayText(items[i].displayName, 120)
            if (displayName.length > 0) {
                displayNames[providerID] = displayName
            }
            if (items[i].enabled === true && !hasOwnKey(seenProviderIDs, providerID)) {
                seenProviderIDs[providerID] = true
                providerIDs.push(providerID)
            }
        }
    }
    return {
        providerIDs: providerIDs,
        displayNames: displayNames
    }
}

function providerSnapshotHasError(item) {
    return isCliRecord(item)
        && item.error !== undefined
        && item.error !== null
        && String(item.error).trim().length > 0
}

// Provider tabs are keyed by canonical provider id. Keep their model unique and
// retain the first healthy snapshot when a malformed payload repeats an id.
function dedupeProviderSnapshots(items) {
    var result = []
    var indexes = ({})
    if (!Array.isArray(items)) {
        return result
    }
    var itemLimit = Math.min(items.length, maximumProviderSnapshots)
    for (var i = 0; i < itemLimit; i++) {
        var item = isCliRecord(items[i]) ? items[i] : null
        var providerID = item ? normalizedProviderID(item.provider) : ""
        if (providerID.length === 0) {
            continue
        }
        var snapshot = copyObject(item)
        snapshot.provider = providerID
        var hasError = providerSnapshotHasError(item)
        if (!hasOwnKey(indexes, providerID)) {
            indexes[providerID] = result.length
            result.push(snapshot)
            continue
        }
        var existingIndex = indexes[providerID]
        var existing = result[existingIndex]
        var existingHasError = providerSnapshotHasError(existing)
        if (existingHasError && !hasError) {
            result[existingIndex] = snapshot
        }
    }
    return result
}

function normalizeCodexCreditLimit(providerID, creditLimit) {
    if (normalizedProviderID(providerID) !== "codex" || !isCliRecord(creditLimit)) {
        return null
    }

    var requiredAmountFields = ["used", "limit", "remaining", "remainingPercent"]
    for (var fieldIndex = 0; fieldIndex < requiredAmountFields.length; fieldIndex++) {
        if (!hasOwnKey(creditLimit, requiredAmountFields[fieldIndex])) {
            return null
        }
    }

    var used = strictFiniteNumber(creditLimit.used)
    var limit = strictFiniteNumber(creditLimit.limit)
    var remaining = strictFiniteNumber(creditLimit.remaining)
    var remainingPercent = strictFiniteNumber(creditLimit.remainingPercent)
    if (!isFinite(used) || used < 0
            || !isFinite(limit) || limit <= 0
            || !isFinite(remaining) || remaining < 0
            || !isFinite(remainingPercent)) {
        return null
    }

    remainingPercent = clamp(remainingPercent, 0, 100)
    return {
        title: boundedDisplayText(hasOwnKey(creditLimit, "title") ? creditLimit.title : "", 120),
        used: used,
        limit: limit,
        remaining: remaining,
        usedPercent: 100 - remainingPercent,
        leftPercent: remainingPercent,
        resetsAt: boundedDisplayText(hasOwnKey(creditLimit, "resetsAt") ? creditLimit.resetsAt : "", 128)
    }
}

// The numeric half of one usage row. `null` when the payload carries no window
// record at all, which is how the caller distinguishes "no such window" from
// "window present but percentage unknown" (`hasPercent === false`).
//
// A provider that reports 137% used, or a negative percentage, must not paint
// outside its meter, so both the used and the pace percentages are clamped.
// `pacePercent` is -1 rather than 0 when the CLI omits it: an omitted pace is
// not a pace of zero, and a marker drawn at 0 would claim the provider is
// comfortably ahead of schedule.
function rateWindowMetrics(window, pace, usageKnown) {
    if (!isCliRecord(window)) {
        return null
    }

    var known = usageKnown !== false
    var used = strictFiniteNumber(window.usedPercent)
    var hasPercent = known && isFinite(used)
    var expectedUsed = strictFiniteNumber(pace && pace.expectedUsedPercent)
    var paceEta = strictFiniteNumber(pace && pace.etaSeconds)
    var paceValue = isFinite(expectedUsed)
        ? clamp(expectedUsed, 0, 100)
        : -1
    return {
        hasPercent: hasPercent,
        usedPercent: hasPercent ? clamp(used, 0, 100) : 0,
        leftPercent: hasPercent ? clamp(100 - used, 0, 100) : 0,
        pacePercent: paceValue,
        paceOnTop: !pace || pace.willLastToReset !== false,
        paceEtaSeconds: isFinite(paceEta)
            ? Math.max(0, Math.min(maximumPaceEtaSeconds, paceEta))
            : 0
    }
}

function statusSeverity(status) {
    if (!status) {
        return ""
    }
    var indicator = String(status.indicator || "").toLowerCase()
    switch (indicator) {
    case "minor":
    case "maintenance":
    case "major":
    case "critical":
    case "unknown":
        return indicator
    default:
        return ""
    }
}

function statusIncidentKey(status) {
    if (!status) {
        return ""
    }
    var keys = [
        "incidentId",
        "incident_id",
        "incidentID",
        "id"
    ]
    for (var i = 0; i < keys.length; i++) {
        var value = status[keys[i]]
        if (value !== null && value !== undefined && String(value).length > 0) {
            return String(value)
        }
    }
    var incident = status.incident || null
    if (incident && incident.id !== null && incident.id !== undefined && String(incident.id).length > 0) {
        return String(incident.id)
    }
    return ""
}

function httpsUrlHost(url) {
    var match = String(url || "").trim().match(/^https:\/\/([^\/?#]+)/i)
    return match ? match[1].toLowerCase() : ""
}

// A provider-supplied status URL is honored only when it stays on the host of
// the URL we already ship for that provider, so a compromised payload cannot
// point the status action anywhere else. The fallback is passed in rather than
// looked up here, which keeps the host comparison testable on its own.
function safeStatusUrl(fallbackStatusUrl, url) {
    var fallback = String(fallbackStatusUrl || "")
    var fallbackHost = httpsUrlHost(fallback)
    var candidate = String(url || "").trim()
    var candidateHost = httpsUrlHost(candidate)
    if (fallbackHost.length === 0) {
        return ""
    }
    if (candidateHost.length === 0) {
        return fallback
    }
    return candidateHost === fallbackHost ? candidate : fallback
}

function accountLabel(item) {
    if (!item) {
        return ""
    }
    if (item.account && item.account.length > 0) {
        return item.account
    }
    if (item.organization && item.organization.length > 0) {
        return item.organization
    }
    if (item.loginMethod && item.loginMethod.length > 0) {
        return item.loginMethod
    }
    return ""
}

function dedupeAccountOptions(items) {
    var seen = ({})
    var result = []
    for (var i = 0; i < items.length; i++) {
        var label = accountLabel(items[i])
        var key = "account:" + label
        if (label.length === 0 || hasOwnKey(seen, key)) {
            continue
        }
        seen[key] = true
        result.push(items[i])
    }
    return result
}

function isMissingTokenAccountsError(errorMessage) {
    // codexbar --all-accounts reports "No token accounts configured for
    // <provider>." even when the provider works through OAuth/CLI auth
    // without named token accounts; that is an empty list, not a failure.
    return String(errorMessage || "").toLowerCase().indexOf("no token accounts configured") !== -1
}

function normalizeSession(item) {
    if (!isCliRecord(item)) {
        return null
    }

    var providerID = normalizedProviderID(item.provider)
    var projectName = boundedDisplayText(item.projectName, 160)
    var sessionName = boundedDisplayText(item.sessionName, 240)
    var host = boundedDisplayText(item.host, 160)
    var state = boundedDisplayText(item.state, 40).toLowerCase()
    var sourceName = boundedDisplayText(item.source, 80)
    var activityAt = boundedDisplayText(item.lastActivityAt, 128)
    var activityMs = Date.parse(activityAt)
    if (!isFinite(activityMs)) {
        activityAt = boundedDisplayText(item.startedAt, 128)
        activityMs = Date.parse(activityAt)
    }
    if (!isFinite(activityMs)) {
        activityAt = ""
        activityMs = 0
    }
    if (providerID.length === 0 && projectName.length === 0 && sessionName.length === 0) {
        return null
    }

    return {
        provider: providerID,
        projectName: projectName,
        sessionName: sessionName,
        host: host,
        state: state,
        source: sourceName,
        activityAt: activityAt,
        activityMs: activityMs
    }
}

// `null` for a payload shape we do not recognize, which the caller reports as an
// error. An unrecognized shape must not read as an empty successful snapshot,
// because that would silently drop the sessions the user was already looking at.
function normalizeSessions(payload) {
    var items
    if (Array.isArray(payload)) {
        items = payload
    } else if (isCliRecord(payload) && Array.isArray(payload.sessions)) {
        items = payload.sessions
    } else {
        return null
    }

    // The bound applies before the sort, so the kept slice is the first
    // `maximumSessions` entries in payload order, then ordered newest first.
    // (Pinned by test_sortsSessionsByRecentActivityAndTruncatesAtTheBound.)
    var nextSessions = []
    var itemLimit = Math.min(items.length, maximumSessions)
    for (var i = 0; i < itemLimit; i++) {
        var normalized = normalizeSession(items[i])
        if (normalized) {
            nextSessions.push(normalized)
        }
    }
    nextSessions.sort(function(a, b) { return b.activityMs - a.activityMs })
    return nextSessions
}

// NaN when no part is usable, so the caller can tell "no token data at all" from
// a genuine zero and fall back to the emitted total instead.
function sumTokenParts(inputTokens, outputTokens, cacheReadTokens, cacheCreationTokens) {
    var total = 0
    var values = [inputTokens, outputTokens, cacheReadTokens, cacheCreationTokens]
    for (var i = 0; i < values.length; i++) {
        var value = strictFiniteNumber(values[i])
        if (isFinite(value) && value > 0) {
            total += value
        }
    }
    return total > 0 ? total : Number.NaN
}

function boundedHistoryDays(days) {
    var numericDays = strictFiniteNumber(days)
    return isFinite(numericDays)
        ? Math.max(1, Math.min(maximumCostHistoryPoints, numericDays))
        : 30
}

function calendarDateKey(year, month, day) {
    var monthText = month < 10 ? "0" + month : String(month)
    var dayText = day < 10 ? "0" + day : String(day)
    return String(year) + "-" + monthText + "-" + dayText
}

function parsedCalendarDateKey(value) {
    var match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(value || ""))
    if (!match) {
        return null
    }
    var year = Number(match[1])
    var month = Number(match[2])
    var day = Number(match[3])
    if (year < 1970 || month < 1 || month > 12 || day < 1 || day > 31) {
        return null
    }
    var timestampMs = Date.UTC(year, month - 1, day)
    var date = new Date(timestampMs)
    if (date.getUTCFullYear() !== year
            || date.getUTCMonth() !== month - 1
            || date.getUTCDate() !== day) {
        return null
    }
    return { key: calendarDateKey(year, month, day), timestampMs: timestampMs }
}

function localCalendarDateKey(value) {
    if (typeof value !== "string" || value.trim().length === 0 || value.length > 100) {
        return ""
    }
    var dateOnly = parsedCalendarDateKey(value.trim())
    if (dateOnly) {
        return dateOnly.key
    }
    var date = new Date(value)
    if (!isFinite(date.getTime())) {
        return ""
    }
    return calendarDateKey(date.getFullYear(), date.getMonth() + 1, date.getDate())
}

function fillMissingCostDays(rows, currency, days, updatedAt, blockedDateKeys) {
    if (!rows || rows.length === 0) {
        return rows || []
    }
    var endDate = parsedCalendarDateKey(localCalendarDateKey(updatedAt))
    if (!endDate) {
        return rows
    }

    var historyDays = Math.floor(boundedHistoryDays(days))
    var dayMilliseconds = 24 * 60 * 60 * 1000
    var firstTimestampMs = endDate.timestampMs - (historyDays - 1) * dayMilliseconds
    var byDate = ({})
    var hasObservedCost = false
    for (var i = 0; i < rows.length; i++) {
        var parsed = parsedCalendarDateKey(rows[i].label)
        if (!parsed || hasOwnKey(byDate, parsed.key)) {
            return rows
        }
        byDate[parsed.key] = rows[i]
        hasObservedCost = hasObservedCost
            || (parsed.timestampMs >= firstTimestampMs
                && parsed.timestampMs <= endDate.timestampMs
                && typeof rows[i].cost === "number"
                && isFinite(rows[i].cost))
    }

    var result = []
    var observedInRange = false
    var safeCurrency = boundedDisplayText(currency || "USD", 12)
    for (var offset = 0; offset < historyDays; offset++) {
        var date = new Date(firstTimestampMs + offset * dayMilliseconds)
        var key = calendarDateKey(
            date.getUTCFullYear(), date.getUTCMonth() + 1, date.getUTCDate())
        if (hasOwnKey(blockedDateKeys, key) && !hasOwnKey(byDate, key)) {
            return rows
        }
        if (hasOwnKey(byDate, key)) {
            result.push(byDate[key])
            observedInRange = true
        } else {
            result.push({
                label: key,
                cost: hasObservedCost ? 0 : null,
                tokens: 0,
                inputTokens: 0,
                outputTokens: 0,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                currency: safeCurrency
            })
        }
    }
    return observedInRange ? result : rows
}

function normalizedCostCoverage(coverage) {
    if (!isCliRecord(coverage)) {
        return null
    }

    var fields = ["priced", "unpriced", "unmetered", "estimated"]
    var result = ({})
    for (var i = 0; i < fields.length; i++) {
        var field = fields[i]
        if (!hasOwnKey(coverage, field)) {
            return null
        }
        var value = coverage[field]
        if (typeof value !== "number"
                || !isFinite(value)
                || Math.floor(value) !== value
                || value < 0
                || value > maximumCostCoverageCount) {
            return null
        }
        result[field] = value
    }
    return result
}

// `coverage` and `provenance` describe how trustworthy the top-level cost
// figures are. Preserve only the official bounded contract and translate the
// provenance wire enum before the snapshot becomes QML state; older payloads
// and records whose two axes are both unusable remain quiet.
function normalizeCostTrustMetadata(rawCostRecord) {
    if (!isCliRecord(rawCostRecord)) {
        return null
    }

    var coverage = hasOwnKey(rawCostRecord, "coverage")
        ? normalizedCostCoverage(rawCostRecord.coverage)
        : null
    var sourceKind = ""
    if (hasOwnKey(rawCostRecord, "provenance")
            && typeof rawCostRecord.provenance === "string") {
        switch (rawCostRecord.provenance) {
        case "listPriceEstimate":
            sourceKind = "listPrice"
            break
        case "vendorMetered":
            sourceKind = "vendor"
            break
        case "mixed":
        case "unknown":
            sourceKind = rawCostRecord.provenance
            break
        }
    }

    return coverage !== null || sourceKind.length > 0
        ? { coverage: coverage, sourceKind: sourceKind }
        : null
}

function costRecordHasError(item) {
    return isCliRecord(item)
        && hasOwnKey(item, "error")
        && item.error !== null
        && item.error !== undefined
}

function normalizeCostEnvelope(payload) {
    var items
    if (Array.isArray(payload)) {
        if (payload.length === 0) {
            return []
        }
        items = payload
    } else if (isCliRecord(payload)) {
        items = [payload]
    } else {
        return null
    }

    var result = []
    var itemLimit = Math.min(items.length, maximumCostSnapshots)
    for (var i = 0; i < itemLimit; i++) {
        var item = items[i]
        if (!isCliRecord(item)) {
            continue
        }
        var providerID = normalizedProviderID(item.provider)
        var itemHasError = costRecordHasError(item)
        if (providerID.length === 0 && itemHasError) {
            return null
        }
        if (providerID.length === 0) {
            continue
        }
        var snapshot = copyObject(item)
        snapshot.provider = providerID
        result.push(snapshot)
    }
    return result.length > 0 ? result : null
}

// A partial cost response is a complete fresh snapshot except for the providers
// named by error records. Carry only those providers forward; copying the whole
// previous map would retain providers that the CLI no longer reports.
function mergeCostSnapshotsAfterPartialFailure(previousSnapshots, freshSnapshots,
        failedProviderIDs) {
    var merged = isCliRecord(freshSnapshots) ? copyObject(freshSnapshots) : ({})
    if (!isCliRecord(previousSnapshots) || !Array.isArray(failedProviderIDs)) {
        return merged
    }
    var itemLimit = Math.min(failedProviderIDs.length, maximumCostSnapshots)
    for (var i = 0; i < itemLimit; i++) {
        var providerID = normalizedProviderID(failedProviderIDs[i])
        if (providerID.length > 0
                && !hasOwnKey(merged, providerID)
                && hasOwnKey(previousSnapshots, providerID)) {
            merged[providerID] = previousSnapshots[providerID]
        }
    }
    return merged
}

function normalizeCostDaily(items, currency, days, updatedAt) {
    var result = []
    if (!items || !Array.isArray(items)) {
        return result
    }

    var historyDays = boundedHistoryDays(days)
    var blockedDateKeys = ({})
    var inspectedItems = 0
    for (var i = items.length - 1; i >= 0
            && result.length < historyDays
            && inspectedItems < maximumCostHistoryScanItems; i--) {
        inspectedItems++
        var item = isCliRecord(items[i]) ? items[i] : null
        if (!item) {
            continue
        }
        var label = boundedDisplayText(item.date || item.day || item.dayKey || "", 120)
        var cost = firstStrictFiniteNumber(item.totalCost, item.costUSD)
        var tokens = firstStrictFiniteNumber(item.totalTokens, item.tokens)
        var inputTokens = strictFiniteNumber(item.inputTokens)
        var outputTokens = strictFiniteNumber(item.outputTokens)
        var cacheReadTokens = strictFiniteNumber(item.cacheReadTokens)
        var cacheCreationTokens = firstStrictFiniteNumber(
            item.cacheCreationTokens, item.cacheWriteTokens)
        if (!isFinite(tokens)) {
            tokens = sumTokenParts(inputTokens, outputTokens, cacheReadTokens, cacheCreationTokens)
        }
        if (!isFinite(cost) && !isFinite(tokens) && !isFinite(inputTokens) && !isFinite(outputTokens)) {
            var blockedDate = parsedCalendarDateKey(label)
            if (blockedDate) {
                blockedDateKeys[blockedDate.key] = true
            }
            continue
        }
        result.unshift({
            label: label,
            cost: isFinite(cost) ? Math.max(0, cost) : null,
            tokens: isFinite(tokens) ? Math.max(0, tokens) : 0,
            inputTokens: isFinite(inputTokens) ? Math.max(0, inputTokens) : 0,
            outputTokens: isFinite(outputTokens) ? Math.max(0, outputTokens) : 0,
            cacheReadTokens: isFinite(cacheReadTokens) ? Math.max(0, cacheReadTokens) : 0,
            cacheCreationTokens: isFinite(cacheCreationTokens) ? Math.max(0, cacheCreationTokens) : 0,
            currency: boundedDisplayText(currency || "USD", 12)
        })
    }
    if (i >= 0) {
        return result
    }
    return fillMissingCostDays(result, currency, historyDays, updatedAt, blockedDateKeys)
}

function normalizeCostTotals(totals, fallbackCost, fallbackTokens, currency) {
    var source = totals || ({})
    var cost = firstStrictFiniteNumber(source.totalCost, fallbackCost)
    var tokens = firstStrictFiniteNumber(source.totalTokens, fallbackTokens)
    var inputTokens = strictFiniteNumber(source.inputTokens)
    var outputTokens = strictFiniteNumber(source.outputTokens)
    var cacheReadTokens = strictFiniteNumber(source.cacheReadTokens)
    var cacheCreationTokens = firstStrictFiniteNumber(
        source.cacheCreationTokens, source.cacheWriteTokens)
    if (!isFinite(tokens)) {
        tokens = sumTokenParts(inputTokens, outputTokens, cacheReadTokens, cacheCreationTokens)
    }
    return {
        cost: isFinite(cost) ? Math.max(0, cost) : null,
        tokens: isFinite(tokens) ? Math.max(0, tokens) : 0,
        inputTokens: isFinite(inputTokens) ? Math.max(0, inputTokens) : 0,
        outputTokens: isFinite(outputTokens) ? Math.max(0, outputTokens) : 0,
        cacheReadTokens: isFinite(cacheReadTokens) ? Math.max(0, cacheReadTokens) : 0,
        cacheCreationTokens: isFinite(cacheCreationTokens) ? Math.max(0, cacheCreationTokens) : 0,
        currency: boundedDisplayText(currency || "USD", 12)
    }
}

// CodexBar 0.56.2 reports zero cost for an established-empty Antigravity
// history even though that provider has no dollar pricing. Keep this
// compatibility rule at the provider boundary so generic zeroes stay valid.
function normalizeProviderCostTotals(providerID, totals, fallbackCost,
        fallbackTokens, currency) {
    var result = normalizeCostTotals(
        totals, fallbackCost, fallbackTokens, currency)
    if (normalizedProviderID(providerID) === "antigravity") {
        result.cost = null
    }
    return result
}

function normalizeCostModels(items, currency, days) {
    var byName = ({})
    if (!items || !Array.isArray(items)) {
        return []
    }

    var historyDays = boundedHistoryDays(days)
    var firstItem = Math.max(0, items.length - historyDays)
    for (var i = firstItem; i < items.length; i++) {
        var breakdowns = items[i] && Array.isArray(items[i].modelBreakdowns)
            ? items[i].modelBreakdowns
            : []
        var breakdownLimit = Math.min(breakdowns.length, maximumModelBreakdownsPerDay)
        for (var j = 0; j < breakdownLimit; j++) {
            var breakdown = breakdowns[j] || ({})
            var name = boundedDisplayText(breakdown.modelName || breakdown.model || "", 120)
            if (name.length === 0 || isUnsafeObjectKey(name)) {
                continue
            }
            var cost = firstStrictFiniteNumber(breakdown.cost, breakdown.totalCost)
            var tokens = firstStrictFiniteNumber(
                breakdown.totalTokens, breakdown.tokens)
            if (!isFinite(cost) && !isFinite(tokens)) {
                continue
            }
            if (!hasOwnKey(byName, name)) {
                byName[name] = {
                    label: name,
                    cost: null,
                    tokens: 0,
                    currency: boundedDisplayText(currency || "USD", 12)
                }
            }
            if (isFinite(cost)) {
                byName[name].cost = (byName[name].cost === null
                    ? 0 : byName[name].cost) + Math.max(0, cost)
            }
            if (isFinite(tokens)) {
                byName[name].tokens += Math.max(0, tokens)
            }
        }
    }

    var rows = []
    for (var modelName in byName) {
        if (!hasOwnKey(byName, modelName)) {
            continue
        }
        rows.push(byName[modelName])
    }
    rows.sort(function(a, b) {
        var aCost = a.cost === null ? 0 : a.cost
        var bCost = b.cost === null ? 0 : b.cost
        if (bCost !== aCost) {
            return bCost - aCost
        }
        return b.tokens - a.tokens
    })
    return rows.slice(0, 6)
}
