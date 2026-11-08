.pragma library
.import "Guards.js" as Guards
.import "ProviderIdentity.js" as ProviderIdentity
.import "SafeText.js" as SafeText

// Pure normalization of untrusted `codexbar` CLI payloads.
// QML owns effects and localization; these helpers return bounded semantic data.
// Collection bounds limit allocations and delegates for malformed payloads.
// Security checks and direct normalizer QtTests cover these limits.

var maximumProviderSnapshots = 256
var maximumAccountSnapshots = 128
var maximumAccountIdentityLength = 256
var maximumCostSnapshots = 256
var maximumCostProjects = 128
var maximumExtraRateWindows = 24

// The official `extraRateWindows[].id` identifies a named quota window. Only a
// short identifier-shaped value is kept; it is matched, never displayed.
function extraWindowID(value) {
    return typeof value === "string" && /^[A-Za-z0-9._:-]{1,64}$/.test(value) ? value : ""
}
var maximumSessions = 128
var maximumCostHistoryPoints = 365
var maximumCostHistoryScanItems = 2048
var maximumModelBreakdownsPerDay = 128
var maximumCostModelRows = 6
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

function nonEmptyString(value) {
    return typeof value === "string" && value.length > 0
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
    return ProviderIdentity.normalizedProviderID(value)
}

// A scoped response may omit its identity in legacy account records, or carry
// a command-wide CLI error. An explicit different provider is never its data.
function providerMatchesScope(item, providerID) {
    if (!hasOwnKey(item, "provider")) return true
    var actual = normalizedProviderID(item.provider)
    return actual === providerID
        || (actual === "cli" && isCliRecord(item.error))
}

function providerConfigEntry(item) {
    if (!isCliRecord(item) || typeof ownField(item, "enabled") !== "boolean") return null
    var providerID = normalizedProviderID(item.provider)
    if (providerID.length === 0) return null
    return { provider: providerID, enabled: item.enabled,
        displayName: boundedDisplayText(item.displayName, 120) }
}

// `config providers` output reduced to the enabled provider ids plus every
// display name it carried. A disabled provider still contributes its name,
// because the popup labels providers it learns about from a later usage payload.
// null means the envelope had no provider-config records. An empty array is a
// valid success and remains distinguishable from an error-shaped JSON payload.
function normalizeProviderConfigEntries(payload) {
    var providerIDs = []
    var displayNames = ({})
    var seenProviderIDs = ({})
    var items = Array.isArray(payload) ? payload : [payload]
    var sawProviderConfigEntry = items.length === 0
    var itemLimit = Math.min(items.length, maximumProviderSnapshots)
    for (var i = 0; i < itemLimit; i++) {
        var entry = providerConfigEntry(items[i])
        if (!entry) continue
        sawProviderConfigEntry = true
        if (entry.displayName.length > 0) displayNames[entry.provider] = entry.displayName
        if (entry.enabled && !hasOwnKey(seenProviderIDs, entry.provider)) {
            seenProviderIDs[entry.provider] = true
            providerIDs.push(entry.provider)
        }
    }
    return sawProviderConfigEntry ? { providerIDs: providerIDs, displayNames: displayNames } : null
}

function providerSnapshotHasError(item) {
    return isCliRecord(item)
        && (item.commandFailed === true || (item.error !== undefined
            && item.error !== null
            && String(item.error).trim().length > 0))
}

function canonicalProviderSnapshot(item) {
    if (!isCliRecord(item)) return null
    var providerID = normalizedProviderID(item.provider)
    if (providerID.length === 0) return null
    var snapshot = copyObject(item)
    snapshot.provider = providerID
    return snapshot
}

// Provider tabs are keyed by canonical provider id. Keep their model unique and
// retain the first healthy snapshot when a malformed payload repeats an id.
function dedupeProviderSnapshots(items) {
    var result = []
    var indexes = ({})
    if (!Array.isArray(items)) return result
    var itemLimit = Math.min(items.length, maximumProviderSnapshots)
    for (var i = 0; i < itemLimit; i++) {
        var snapshot = canonicalProviderSnapshot(items[i])
        if (!snapshot) continue
        var providerID = snapshot.provider
        if (!hasOwnKey(indexes, providerID)) {
            indexes[providerID] = result.length
            result.push(snapshot)
            continue
        }
        var existingIndex = indexes[providerID]
        if (providerSnapshotHasError(result[existingIndex]) && !providerSnapshotHasError(items[i])) {
            result[existingIndex] = snapshot
        }
    }
    return result
}

function ownField(item, key) {
    return hasOwnKey(item, key) ? item[key] : undefined
}

function isNonNegativeNumber(value) {
    return isFinite(value) && value >= 0
}

function normalizeCodexCreditLimit(providerID, creditLimit) {
    if (normalizedProviderID(providerID) !== "codex" || !isCliRecord(creditLimit)) return null
    var used = strictFiniteNumber(ownField(creditLimit, "used"))
    var limit = strictFiniteNumber(ownField(creditLimit, "limit"))
    var remaining = strictFiniteNumber(ownField(creditLimit, "remaining"))
    var remainingPercent = strictFiniteNumber(ownField(creditLimit, "remainingPercent"))
    if (!isNonNegativeNumber(used) || !isNonNegativeNumber(remaining)) return null
    if (!isFinite(limit) || limit <= 0 || !isFinite(remainingPercent)) return null
    remainingPercent = clamp(remainingPercent, 0, 100)
    return {
        title: boundedDisplayText(ownField(creditLimit, "title"), 120),
        used: used,
        limit: limit,
        remaining: remaining,
        usedPercent: 100 - remainingPercent,
        leftPercent: remainingPercent,
        resetsAt: boundedDisplayText(ownField(creditLimit, "resetsAt"), 128)
    }
}

// Missing confidence keeps legacy payloads compatible. Future or malformed
// values are bounded to a semantic unknown, never promoted to measured quota.
function usageConfidence(value) {
    if (value === undefined || value === "") {
        return ""
    }
    return value === "exact" || value === "estimated" || value === "percentOnly" ? value : "unknown"
}

// CLI and persisted records use field absence for legacy confidence. The empty
// marker belongs only to normalized in-memory snapshots, never to raw input.
function usageConfidenceField(record) {
    return hasOwnKey(record, "dataConfidence")
        ? (usageConfidence(record.dataConfidence) || "unknown") : ""
}

function authoritativeQuota(row) {
    var confidence = usageConfidence(row && row.dataConfidence)
    return confidence === "" || confidence === "exact"
}

// Percentage-only readings can carry explicit CLI resets and forecasts.
// Present those details without authorizing quota automation from the reading.
function canPresentQuotaDetails(row) {
    return !!row && (authoritativeQuota(row) || usageConfidence(row.dataConfidence) === "percentOnly")
}

function paceForecastKnown(pace, eta) {
    if (!isCliRecord(pace) || typeof ownField(pace, "willLastToReset") !== "boolean") return false
    return pace.willLastToReset === true || (isFinite(eta) && eta > 0)
}

function paceMetrics(pace) {
    var expectedUsed = strictFiniteNumber(pace && pace.expectedUsedPercent)
    var eta = strictFiniteNumber(pace && pace.etaSeconds)
    return {
        paceKnown: paceForecastKnown(pace, eta),
        pacePercent: isFinite(expectedUsed) ? clamp(expectedUsed, 0, 100) : -1,
        paceOnTop: !pace || pace.willLastToReset !== false,
        paceEtaSeconds: isFinite(eta) ? clamp(eta, 0, maximumPaceEtaSeconds) : 0
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
    if (!isCliRecord(window)) return null
    var used = strictFiniteNumber(window.usedPercent)
    var hasPercent = usageKnown !== false && isFinite(used)
    var result = paceMetrics(pace)
    result.hasPercent = hasPercent
    result.usedPercent = hasPercent ? clamp(used, 0, 100) : 0
    result.leftPercent = hasPercent ? clamp(100 - used, 0, 100) : 0
    result.windowMinutes = rateWindowMinutes(window.windowMinutes)
    return result
}

// The window length the CLI reports beside `resetsAt` (10080 for a weekly
// limit). Anything but a whole number of minutes up to a year is dropped to 0,
// which consumers read as "length unknown".
function rateWindowMinutes(value) {
    return typeof value === "number" && isFinite(value) && Math.floor(value) === value
        && value > 0 && value <= 366 * 24 * 60 ? value : 0
}

// CLI-controlled text that must never throw while being read. Only genuine
// scalars survive: coercing an object runs its toString, which a malformed
// payload may have nulled, and would otherwise abort the whole refresh.
function safeScalarText(value) {
    if (typeof value === "string") {
        return value
    }
    if (typeof value === "number" || typeof value === "boolean") {
        return String(value)
    }
    return ""
}

function statusSeverity(status) {
    if (!status) {
        return ""
    }
    var indicator = safeScalarText(status.indicator).toLowerCase()
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
        var text = safeScalarText(status[keys[i]])
        if (text.length > 0) {
            return text
        }
    }
    var incident = status.incident || null
    var incidentText = incident ? safeScalarText(incident.id) : ""
    if (incidentText.length > 0) {
        return incidentText
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
    var candidate = typeof url === "string" ? url.trim() : ""
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
    if (typeof item.account === "string" && item.account.length > 0) {
        return item.account
    }
    if (typeof item.organization === "string" && item.organization.length > 0) {
        return item.organization
    }
    if (typeof item.loginMethod === "string" && item.loginMethod.length > 0) {
        return item.loginMethod
    }
    return ""
}

// The account selection identity: validated, never rewritten. Display text may
// collapse whitespace, redact, and truncate, but none of that may feed back
// into result matching or the `--account` argument, where two names that differ only
// by collapsed characters still address different accounts. A normalized
// snapshot already carries its validated key; recomputing it from the
// collapsed display fields would lose the original spacing, so a carried key
// is reused once it passes the same blank and length checks as a fresh
// candidate. Overlong or non-string identities carry no key and stay
// display-only.
function validAccountIdentity(value) {
    return typeof value === "string" && value.trim().length > 0
        && value.length <= maximumAccountIdentityLength
}

function accountKey(item) {
    if (!isCliRecord(item)) return ""
    if (validAccountIdentity(item.accountKey)) return item.accountKey
    var candidates = [item.account, item.organization, item.loginMethod]
    for (var i = 0; i < candidates.length; i++) {
        if (typeof candidates[i] !== "string") continue
        var identity = candidates[i].trim()
        if (validAccountIdentity(identity)) return identity
    }
    return ""
}

// First candidate that survives the account-identity validation. A truthy but
// structured value must not mask a valid fallback: `accountKey` skips
// non-strings, so selecting `item.account || identity.accountEmail` directly
// would keep an object and lose the fallback identity.
function firstValidAccountIdentity(candidates) {
    if (!Array.isArray(candidates)) {
        return ""
    }
    for (var i = 0; i < candidates.length; i++) {
        if (typeof candidates[i] === "string"
                && accountKey({ account: candidates[i] }).length > 0) {
            return candidates[i]
        }
    }
    return ""
}

function accountOptionKey(item) {
    var key = accountKey(item)
    if (key.length > 0) {
        return "key:" + key
    }
    var label = accountLabel(item)
    if (label.length === 0) {
        return ""
    }
    return "label:" + label
}

// Keep each account's position and first healthy record, as for provider
// snapshots. A failed duplicate must not hide a successful account read.
function dedupeAccountOptions(items) {
    if (!Array.isArray(items)) {
        return []
    }
    var indexes = ({})
    var result = []
    var itemLimit = Math.min(items.length, maximumAccountSnapshots)
    for (var i = 0; i < itemLimit; i++) {
        var key = accountOptionKey(items[i])
        if (key.length === 0) {
            continue
        }
        if (!hasOwnKey(indexes, key)) {
            indexes[key] = result.length
            result.push(items[i])
        } else if (providerSnapshotHasError(result[indexes[key]])
                && !providerSnapshotHasError(items[i])) {
            result[indexes[key]] = items[i]
        }
    }
    return result
}

function isMissingTokenAccountsError(errorMessage) {
    // codexbar --all-accounts reports "No token accounts configured for
    // <provider>." even when the provider works through OAuth/CLI auth
    // without named token accounts; that is an empty list, not a failure.
    return String(errorMessage || "").toLowerCase().indexOf("no token accounts configured") !== -1
}

function isUnsupportedTokenAccountsError(errorMessage) {
    // codexbar --all-accounts rejects providers without token-account support
    // with "<provider> does not support token accounts." (Linux 0.76.0/0.77.0).
    return String(errorMessage || "").toLowerCase().indexOf("does not support token accounts") !== -1
}

function normalizeSession(item) {
    if (!isCliRecord(item)) {
        return null
    }

    var providerID = normalizedProviderID(item.provider)
    var projectName = boundedDisplayText(item.projectName, 160)
    var sessionName = boundedDisplayText(item.sessionName, 240)
    var host = boundedDisplayText(item.host, 160)
    var dialect = boundedDisplayText(item.dialect, 40).toLowerCase()
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
        dialect: dialect,
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
    // Dropping unreadable records does not confirm that no sessions exist.
    // Preserve the previous scan when a nonempty reply has no usable records.
    return items.length === 0 || nextSessions.length > 0 ? nextSessions : null
}

// NaN when no nonnegative part is usable; an explicitly measured zero stays zero.
function sumTokenParts(inputTokens, outputTokens, cacheReadTokens, cacheCreationTokens) {
    var total = 0
    var hasObservedPart = false
    var values = [inputTokens, outputTokens, cacheReadTokens, cacheCreationTokens]
    for (var i = 0; i < values.length; i++) {
        var value = strictFiniteNumber(values[i])
        if (isFinite(value) && value >= 0) {
            hasObservedPart = true
            total += value
        }
    }
    return hasObservedPart ? total : Number.NaN
}

// `maximumDays` defaults to the charted bound; aggregates over a longer
// calendar period may pass its span. Record inspection stays separately bounded.
function boundedHistoryDays(days, maximumDays) {
    var numericDays = strictFiniteNumber(days)
    return isFinite(numericDays)
        ? Math.max(1, Math.min(maximumDays || maximumCostHistoryPoints, numericDays))
        : 30
}

function calendarDateKey(year, month, day) {
    var monthText = month < 10 ? "0" + month : String(month)
    var dayText = day < 10 ? "0" + day : String(day)
    return String(year) + "-" + monthText + "-" + dayText
}

function parsedCalendarDateKey(value) {
    if (typeof value !== "string") return null
    var match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value)
    if (!match || Number(match[1]) < 1970) return null
    var timestampMs = Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]))
    var date = new Date(timestampMs)
    var key = calendarDateKey(date.getUTCFullYear(), date.getUTCMonth() + 1, date.getUTCDate())
    // UTC construction rolls invalid days and months; round-trip the whole key.
    return key === value ? { key: key, timestampMs: timestampMs } : null
}

// A CLI calendar key names a local day, not an instant: its local noon keeps
// the same day in zones west of UTC and on days whose local midnight is skipped
// by a spring-forward transition. Null for any other label.
function calendarKeyLocalDate(value) {
    var parsed = parsedCalendarDateKey(value)
    if (!parsed) {
        return null
    }
    var utc = new Date(parsed.timestampMs)
    return new Date(utc.getUTCFullYear(), utc.getUTCMonth(), utc.getUTCDate(), 12)
}

function localCalendarDateKey(value) {
    if (!nonEmptyString(value) || value.length > 100) {
        return ""
    }
    var dateOnly = parsedCalendarDateKey(value.trim())
    if (dateOnly) {
        return dateOnly.key
    }
    // Date() rolls an impossible day such as February 30 into the next month.
    var datePrefix = /^\s*(\d{4}-\d{2}-\d{2})/.exec(value)
    if (datePrefix && !parsedCalendarDateKey(datePrefix[1])) {
        return ""
    }
    var date = new Date(value)
    if (!isFinite(date.getTime())) {
        return ""
    }
    return calendarDateKey(date.getFullYear(), date.getMonth() + 1, date.getDate())
}

function costHistoryCalendarWindow(days, updatedAt, maximumDays) {
    var endDate = parsedCalendarDateKey(localCalendarDateKey(updatedAt))
    if (!endDate) {
        return null
    }
    var historyDays = Math.floor(boundedHistoryDays(days, maximumDays))
    return {
        firstTimestampMs: endDate.timestampMs - (historyDays - 1) * 24 * 60 * 60 * 1000,
        lastTimestampMs: endDate.timestampMs
    }
}

// Gap filling may be unsafe, but valid calendar labels must still stay inside
// the selected window. Undated legacy rows retain their bounded tail behavior.
function costHistoryRowsWithinWindow(rows, window) {
    if (!window) {
        return rows
    }
    return rows.filter(function(row) {
        var parsed = parsedCalendarDateKey(row.label)
        return !parsed || (parsed.timestampMs >= window.firstTimestampMs
            && parsed.timestampMs <= window.lastTimestampMs)
    })
}

function indexedCostDays(rows, window, historyDays) {
    var indexed = { byDate: ({}), hasCost: false, hasTokens: false }
    for (var i = 0; i < rows.length; i++) {
        var parsed = parsedCalendarDateKey(rows[i].label)
        // A malformed retained label or duplicate makes zero-day inference unsafe.
        if (!parsed) {
            if (i >= rows.length - historyDays) return null
            continue
        }
        if (!costDateWithinWindow(parsed, window)) continue
        if (hasOwnKey(indexed.byDate, parsed.key)) return null
        indexed.byDate[parsed.key] = rows[i]
        indexed.hasCost = indexed.hasCost || isObservedCostAmount(rows[i].cost)
        indexed.hasTokens = indexed.hasTokens || isObservedCostAmount(rows[i].tokens)
    }
    return indexed
}

function isObservedCostAmount(value) {
    return typeof value === "number" && isFinite(value)
}

function costDateWithinWindow(parsed, window) {
    return parsed.timestampMs >= window.firstTimestampMs
        && parsed.timestampMs <= window.lastTimestampMs
}

function emptyCostDay(key, currency, indexed) {
    // Only metrics observed in this snapshot can imply zero activity on a gap.
    return {
        label: key,
        cost: indexed.hasCost ? 0 : null,
        tokens: indexed.hasTokens ? 0 : null,
        inputTokens: 0,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheCreationTokens: 0,
        currency: currency,
        models: [],
        modelsTruncated: false
    }
}

function filledCostDays(indexed, window, currency, blockedDateKeys) {
    var result = []
    var observedInRange = false
    var dayMilliseconds = 24 * 60 * 60 * 1000
    for (var timestampMs = window.firstTimestampMs; timestampMs <= window.lastTimestampMs;
            timestampMs += dayMilliseconds) {
        var date = new Date(timestampMs)
        var key = calendarDateKey(
            date.getUTCFullYear(), date.getUTCMonth() + 1, date.getUTCDate())
        var observed = hasOwnKey(indexed.byDate, key)
        if (!observed && hasOwnKey(blockedDateKeys, key)) return null
        observedInRange = observedInRange || observed
        result.push(observed ? indexed.byDate[key] : emptyCostDay(key, currency, indexed))
    }
    // No observation in range must not manufacture a zero-cost history.
    return observedInRange ? result : []
}

function fillMissingCostDays(rows, currency, selection, blockedDateKeys) {
    if (rows.length === 0) return rows
    var window = selection.window
    if (!window) return rows
    var indexed = indexedCostDays(rows, window, selection.historyDays)
    if (!indexed) return costHistoryRowsWithinWindow(rows, window)
    var result = filledCostDays(indexed, window,
        boundedDisplayText(currency || "USD", 12), blockedDateKeys)
    return result === null ? costHistoryRowsWithinWindow(rows, window) : result
}

function isIntegerInRange(value, minimum, maximum) {
    return typeof value === "number" && isFinite(value) && Math.floor(value) === value
        && value >= minimum && value <= maximum
}

function normalizedCostCoverage(coverage) {
    if (!isCliRecord(coverage)) return null
    var fields = ["priced", "unpriced", "unmetered", "estimated"]
    var result = ({})
    for (var i = 0; i < fields.length; i++) {
        var value = ownField(coverage, fields[i])
        if (!isIntegerInRange(value, 0, maximumCostCoverageCount)) return null
        result[fields[i]] = value
    }
    return result
}

// CLI 0.60.5 counts requests that lacked final usage and were excluded from
// the reported tokens and cost. The key is omitted when none were excluded, so
// an absent, malformed, or negative value means "none reported" rather than an
// unknown amount. The upstream sum saturates, so accept the same bound as the
// coverage counts and keep anything larger as the bound.
function normalizedIncompleteRequestCount(value) {
    return isIntegerInRange(value, 1, Infinity) ? Math.min(value, maximumCostCoverageCount) : 0
}

// `coverage`, `provenance`, and the incomplete-request count describe how
// trustworthy the top-level cost figures are. Preserve only the official
// bounded contract and translate the provenance wire enum before the snapshot
// becomes QML state; older payloads and records whose axes are all unusable
// remain quiet.
function costSourceKind(provenance) {
    switch (provenance) {
    case "listPriceEstimate": return "listPrice"
    case "vendorMetered": return "vendor"
    case "mixed":
    case "unknown": return provenance
    default: return ""
    }
}

function normalizeCostTrustMetadata(rawCostRecord) {
    if (!isCliRecord(rawCostRecord)) return null
    var coverage = normalizedCostCoverage(ownField(rawCostRecord, "coverage"))
    var incompleteRequests = normalizedIncompleteRequestCount(rawCostRecord.incompleteRequestCount)
    var sourceKind = costSourceKind(ownField(rawCostRecord, "provenance"))
    return coverage !== null || sourceKind.length > 0 || incompleteRequests > 0
        ? { coverage: coverage, sourceKind: sourceKind, incompleteRequests: incompleteRequests }
        : null
}

function costRecordHasError(item) {
    if (!isCliRecord(item) || !hasOwnKey(item, "error")) {
        return false
    }
    var error = item.error
    if (typeof error === "string") {
        return error.trim().length > 0
    }
    return Boolean(error)
}

function costEnvelopeItems(payload) {
    if (Array.isArray(payload)) return payload
    return isCliRecord(payload) ? [payload] : null
}

function normalizeCostEnvelope(payload) {
    var items = costEnvelopeItems(payload)
    if (!items) return null
    if (items.length === 0) return []
    var result = []
    var itemLimit = Math.min(items.length, maximumCostSnapshots)
    for (var i = 0; i < itemLimit; i++) {
        var item = items[i]
        if (!isCliRecord(item)) continue
        var snapshot = canonicalProviderSnapshot(item)
        if (snapshot) result.push(snapshot)
        else if (costRecordHasError(item)) return null
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
        if (providerID.length === 0 || hasOwnKey(merged, providerID)) continue
        if (hasOwnKey(previousSnapshots, providerID)) {
            merged[providerID] = previousSnapshots[providerID]
        }
    }
    return merged
}

function nonNegativeAmount(value, missing) {
    return isFinite(value) ? Math.max(0, value) : missing
}

function normalizedCostProject(item, currency) {
    if (!isCliRecord(item) || typeof ownField(item, "name") !== "string") return null
    var label = boundedDisplayText(item.name, 120)
    var cost = strictFiniteNumber(ownField(item, "totalCost"))
    var tokens = strictFiniteNumber(ownField(item, "totalTokens"))
    if (label.length === 0 || (!isFinite(cost) && !isFinite(tokens))) return null
    return { label: label, cost: nonNegativeAmount(cost, null),
        tokens: nonNegativeAmount(tokens, null), currency: boundedDisplayText(currency || "USD", 12) }
}

// CLI 0.56.2 projects carry local paths and nested source records. Retain only
// the display name and range totals; project names are labels, never map keys.
function normalizeCostProjects(items, currency) {
    var result = { rows: [], truncated: false }
    if (!Array.isArray(items)) return result
    var limit = Math.min(items.length, maximumCostProjects)
    result.truncated = items.length > limit
    for (var i = 0; i < limit; i++) {
        var row = normalizedCostProject(items[i], currency)
        if (row) result.rows.push(row)
    }
    return result
}

// A record without any cost or token amount is not a day of usage. The daily
// history skips it; the model history also needs it to lack model breakdowns.
function costRecordHasAmounts(item) {
    return isFinite(firstStrictFiniteNumber(item.totalCost, item.costUSD))
        || isFinite(firstStrictFiniteNumber(item.totalTokens, item.tokens))
        || [item.inputTokens, item.outputTokens, item.cacheReadTokens,
            firstStrictFiniteNumber(item.cacheCreationTokens, item.cacheWriteTokens)]
            .some(function(part) {
                var value = strictFiniteNumber(part)
                return isFinite(value) && value >= 0
            })
}

function costDayLabel(item) {
    return boundedDisplayText(item.date || item.day || item.dayKey || "", 120)
}

function normalizedCostDay(item, currency) {
    var row = normalizeCostTotals(item, item.costUSD, item.tokens, currency)
    var modelSummary = costModelSummary([item], currency)
    row.label = costDayLabel(item)
    row.incompleteRequests = normalizedIncompleteRequestCount(item.incompleteRequestCount)
    row.models = modelSummary.rows
    row.modelsTruncated = modelSummary.truncated
    return row
}

// Daily rows and model totals share calendar and input-inspection bounds.
function costHistorySelection(items, options) {
    var historyDays = Math.floor(boundedHistoryDays(options.days, options.maximumDays))
    return {
        historyDays: historyDays,
        firstItem: Math.max(0, items.length - historyDays),
        firstInspectedItem: Math.max(0, items.length - maximumCostHistoryScanItems),
        window: costHistoryCalendarWindow(historyDays, options.updatedAt, options.maximumDays)
    }
}

function normalizeCostDaily(items, currency, options) {
    if (!Array.isArray(items)) return []
    var selection = costHistorySelection(items, options || ({}))
    var historyDays = selection.historyDays
    var blockedDateKeys = ({})
    var firstInspectedItem = selection.firstInspectedItem
    var result = []
    for (var i = items.length - 1; i >= firstInspectedItem; i--) {
        var item = items[i]
        if (!isCliRecord(item)) continue
        if (costRecordHasAmounts(item)) {
            result.unshift(normalizedCostDay(item, currency))
            continue
        }
        var blockedDate = parsedCalendarDateKey(costDayLabel(item))
        if (blockedDate) blockedDateKeys[blockedDate.key] = true
    }
    // An incomplete scan cannot establish safe zero-activity gaps.
    if (firstInspectedItem > 0) {
        return costHistoryRowsWithinWindow(result,
            selection.window).slice(-historyDays)
    }
    return fillMissingCostDays(result, currency, selection, blockedDateKeys)
        .slice(-historyDays)
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
        cost: nonNegativeAmount(cost, null),
        tokens: nonNegativeAmount(tokens, null),
        inputTokens: nonNegativeAmount(inputTokens, 0),
        outputTokens: nonNegativeAmount(outputTokens, 0),
        cacheReadTokens: nonNegativeAmount(cacheReadTokens, 0),
        cacheCreationTokens: nonNegativeAmount(cacheCreationTokens, 0),
        currency: boundedDisplayText(currency || "USD", 12)
    }
}

// CodexBar 0.56.2 reports zero cost for Antigravity when today has no usage
// or the whole history is empty, even though the provider has no pricing.
function normalizeProviderCostAmount(providerID, amount) {
    var cost = strictFiniteNumber(amount)
    return normalizedProviderID(providerID) !== "antigravity" && isFinite(cost)
        ? cost : null
}

function normalizeProviderCostTotals(providerID, totals, fallback) {
    fallback = fallback || ({})
    var result = normalizeCostTotals(totals, fallback.cost, fallback.tokens, fallback.currency)
    result.cost = normalizeProviderCostAmount(providerID, result.cost)
    return result
}

function eligibleCostModelDay(item, itemIndex, selection) {
    if (!isCliRecord(item)) return false
    if (!hasOwnKey(item, "modelBreakdowns") && !costRecordHasAmounts(item)) return false
    if (!selection.window) return true
    var parsed = parsedCalendarDateKey(costDayLabel(item))
    // Undated legacy records retain the original bounded tail behavior.
    return parsed ? costDateWithinWindow(parsed, selection.window) : itemIndex >= selection.firstItem
}

function costModelScanTruncated(selection, retainedDayCount) {
    return selection.firstInspectedItem > 0
        && (selection.window !== null || retainedDayCount < selection.historyDays)
}

function normalizeCostModels(items, currency, options) {
    if (!Array.isArray(items)) return { rows: [], truncated: false }
    options = options || ({})
    var selection = costHistorySelection(items, options)
    var modelDays = []
    for (var itemIndex = items.length - 1; itemIndex >= selection.firstInspectedItem
            && modelDays.length < selection.historyDays; itemIndex--) {
        if (eligibleCostModelDay(items[itemIndex], itemIndex, selection)) {
            modelDays.unshift(items[itemIndex])
        }
    }
    var summary = costModelSummary(modelDays, currency, options.includeTokenRanking)
    if (summary.tokenRanking) {
        summary.tokenRanking.sourceTruncated = summary.tokenRanking.sourceTruncated
            || costModelScanTruncated(selection, modelDays.length)
    }
    return summary
}

function costModelName(breakdown) {
    var name = ownField(breakdown, "modelName")
    return nonEmptyString(name) ? name : ownField(breakdown, "model")
}

function normalizedCostModelBreakdown(breakdown) {
    if (!isCliRecord(breakdown)) return null
    var rawName = costModelName(breakdown)
    // Aggregate by raw identity: bounded, redacted labels can collide.
    if (!nonEmptyString(rawName) || isUnsafeObjectKey(rawName)) return null
    var name = boundedDisplayText(rawName, 120)
    if (name.length === 0) return null
    return {
        key: rawName,
        label: name,
        incompleteRequests: normalizedIncompleteRequestCount(ownField(breakdown, "incompleteRequestCount")),
        cost: firstStrictFiniteNumber(ownField(breakdown, "cost"), ownField(breakdown, "totalCost")),
        tokens: firstStrictFiniteNumber(ownField(breakdown, "totalTokens"), ownField(breakdown, "tokens"))
    }
}

function accumulateCostModelMetric(aggregate, breakdown, metric) {
    var overflowKey = metric + "Overflow"
    if (!isFinite(breakdown[metric]) || aggregate[overflowKey]) return
    var total = (aggregate[metric] === null ? 0 : aggregate[metric]) + Math.max(0, breakdown[metric])
    // Later finite rows must not revive an overflowed sum as a partial total.
    aggregate[overflowKey] = !isFinite(total)
    aggregate[metric] = aggregate[overflowKey] ? null : total
}

function accumulateCostModelAmounts(aggregate, breakdown) {
    if (isFinite(breakdown.tokens) && !isFinite(breakdown.cost)) aggregate.unknownCost = true
    accumulateCostModelMetric(aggregate, breakdown, "cost")
    accumulateCostModelMetric(aggregate, breakdown, "tokens")
}

function addCostModelBreakdown(byName, incompleteByName, breakdown, currency) {
    if (!breakdown) {
        return
    }
    var key = breakdown.key
    if (breakdown.incompleteRequests > 0) {
        incompleteByName[key] = Math.min(maximumCostCoverageCount,
            (hasOwnKey(incompleteByName, key) ? incompleteByName[key] : 0) + breakdown.incompleteRequests)
    }
    if (!isFinite(breakdown.cost) && !isFinite(breakdown.tokens)) {
        return
    }
    if (!hasOwnKey(byName, key)) {
        byName[key] = {
            label: breakdown.label,
            cost: null,
            tokens: null,
            currency: boundedDisplayText(currency || "USD", 12),
            costOverflow: false,
            tokensOverflow: false,
            unknownCost: false
        }
    }
    accumulateCostModelAmounts(byName[key], breakdown)
}

function compareCostModelLabels(a, b) {
    return a.label === b.label ? 0 : (a.label < b.label ? -1 : 1)
}

function compareCostModelAmounts(a, b) {
    var aValue = a === null ? 0 : a
    var bValue = b === null ? 0 : b
    if (aValue === bValue) return 0
    return bValue > aValue ? 1 : -1
}

function compareCostModels(a, b) {
    return compareCostModelAmounts(a.cost, b.cost)
        || compareCostModelAmounts(a.tokens, b.tokens)
        || compareCostModelLabels(a, b)
}

function costModelTokenRanking(rows, truncated, hasUnknownCost) {
    // Rank the full bounded aggregation before the cost-first display cap.
    // A cheap or unpriced model can still have the largest token count.
    var tokenRows = rows.filter(function(row) { return row.tokens !== null })
    tokenRows.sort(function(a, b) {
        return b.tokens - a.tokens || compareCostModelLabels(a, b)
    })
    return {
        rows: tokenRows.slice(0, maximumCostModelRows),
        omitted: Math.max(0, tokenRows.length - maximumCostModelRows),
        truncated: truncated || tokenRows.length > maximumCostModelRows,
        // Display-only omissions are listed separately. Source loss and
        // unknown costs still qualify the export's data notice.
        sourceTruncated: truncated,
        hasUnknownCost: hasUnknownCost || tokenRows.some(function(row) { return row.cost === null })
    }
}

function accumulateCostModelDay(aggregation, item, currency) {
    var breakdowns = hasOwnKey(item, "modelBreakdowns") && Array.isArray(item.modelBreakdowns)
        ? item.modelBreakdowns : []
    var breakdownLimit = Math.min(breakdowns.length, maximumModelBreakdownsPerDay)
    aggregation.truncated = aggregation.truncated || breakdowns.length > breakdownLimit
    for (var i = 0; i < breakdownLimit; i++) {
        addCostModelBreakdown(aggregation.byName, aggregation.incompleteByName,
            normalizedCostModelBreakdown(breakdowns[i]), currency)
    }
}

function costModelSummary(modelDays, currency, includeTokenRanking) {
    // Excluded-only records contribute counts without manufacturing measured amounts.
    var aggregation = { byName: ({}), incompleteByName: ({}), truncated: false }
    for (var i = 0; i < modelDays.length; i++) {
        accumulateCostModelDay(aggregation, modelDays[i], currency)
    }
    var hasUnknownCost = false
    var rows = Object.keys(aggregation.byName).map(function(key) {
        var model = aggregation.byName[key]
        hasUnknownCost = hasUnknownCost || (model.tokens !== null && model.unknownCost)
        return { label: model.label, cost: model.cost, tokens: model.tokens, currency: model.currency,
            incompleteRequests: hasOwnKey(aggregation.incompleteByName, key)
                ? aggregation.incompleteByName[key] : 0 }
    })
    rows.sort(compareCostModels)
    var result = {
        rows: rows.slice(0, maximumCostModelRows),
        truncated: aggregation.truncated || rows.length > maximumCostModelRows
    }
    if (includeTokenRanking === true) {
        result.tokenRanking = costModelTokenRanking(rows, aggregation.truncated, hasUnknownCost)
    }
    return result
}
