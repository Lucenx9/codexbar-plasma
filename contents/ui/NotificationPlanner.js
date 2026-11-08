.pragma library
.import "ProviderNormalizer.js" as Normalizer
.import "Guards.js" as Guards
.import "NotificationMemo.js" as NotificationMemo

// Pure transition kernel for provider notifications. Callers supply normalized
// observations and keep ownership of localization, timers, refresh lifecycle,
// and notification effects. The memo is opaque outside this module: callers
// only retain `nextMemo` and feed it into the next transition.

// One normalized pass can carry 256 providers with 27 usage windows and three
// threshold keys per window. This keeps a complete pass while bounding stale
// account scopes accumulated across a long plasmashell session.
var maximumMemoEntries = 32768

function copyMemo(memo) {
    return Guards.copyObject(memo || ({}))
}

function observationPending(refreshPending, errorPresent, statusKnown, usageRowCount) {
    return refreshPending === true
        || (errorPresent === true
            && statusKnown !== true
            && Number(usageRowCount) === 0)
}

function statusValue(observation) {
    if (!observation || observation.statusActive !== true) {
        return ""
    }
    return NotificationMemo.statusMemoValue(
        observation.statusSeverity,
        observation.statusIncidentKey)
}

function scopePrimedKey(observation) {
    return "scope:" + String(observation.scopeID || "")
}

function rowIdentityValue(row, useResetTimestamp) {
    if (!row) {
        return ""
    }
    var windowID = row.lane === "extra" ? Normalizer.extraWindowID(row.windowId) : ""
    var value = String(useResetTimestamp
        ? (row.resetsAt ? row.resetsAt : "")
        : (row.label ? row.label : ""))
    return JSON.stringify([windowID, windowID.length > 0 && !useResetTimestamp ? "" : value])
}

// Named extra windows use their CLI ID; legacy rows fall back to label/reset.
// Numbering duplicate identities instead of keying on the absolute index keeps
// baseline state stable when the CLI inserts or reorders unrelated windows.
function rowOccurrence(rows, index, useResetTimestamp) {
    var lane = rows[index] && rows[index].lane ? String(rows[index].lane) : ""
    var identity = rowIdentityValue(rows[index], useResetTimestamp)
    var occurrences = 0
    for (var i = 0; i < index; i++) {
        if (rowIdentityValue(rows[i], useResetTimestamp) !== identity) {
            continue
        }
        var priorLane = rows[i] && rows[i].lane ? String(rows[i].lane) : ""
        if (priorLane === lane) {
            occurrences++
        }
    }
    return occurrences
}

function rowIdentity(observation, row, index, useResetTimestamp) {
    var rows = Array.isArray(observation && observation.rows)
        ? observation.rows
        : []
    var lane = row && row.lane ? String(row.lane) : ""
    return lane + ":" + rowIdentityValue(row, useResetTimestamp)
        + ":" + rowOccurrence(rows, index, useResetTimestamp)
}

function quotaKey(observation, row, index) {
    return "quota:" + String(observation.scopeID || "") + ":"
        + rowIdentity(observation, row, index, false)
}

function paceKey(observation, row, index) {
    return "pace:" + String(observation.scopeID || "") + ":"
        + rowIdentity(observation, row, index, true)
}

function resetKey(observation, row, index) {
    return "reset:" + String(observation.scopeID || "") + ":"
        + rowIdentity(observation, row, index, false)
}

function currentMemoKeys(observations) {
    var result = ({})
    var items = Array.isArray(observations) ? observations : []
    for (var i = 0; i < items.length; i++) {
        var item = items[i]
        if (!item) {
            continue
        }
        result[NotificationMemo.statusMemoKey(item.providerID)] = true
        result[NotificationMemo.statusPrimedMemoKey(item.providerID)] = true
        result[scopePrimedKey(item)] = true
        var rows = Array.isArray(item.rows) ? item.rows : []
        for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
            result[quotaKey(item, rows[rowIndex], rowIndex)] = true
            result[paceKey(item, rows[rowIndex], rowIndex)] = true
            result[resetKey(item, rows[rowIndex], rowIndex)] = true
        }
    }
    return result
}

// Select newest keys first, protecting the current observations before using
// the remaining budget for stale account scopes. Copy values in source order.
function retainRecentKeys(keys, keptKeys, eligibleKeys) {
    var keptCount = Object.keys(keptKeys).length
    for (var i = keys.length - 1; i >= 0 && keptCount < maximumMemoEntries; i--) {
        var key = keys[i]
        if (eligibleKeys && !Guards.hasOwnKey(eligibleKeys, key)) {
            continue
        }
        if (!Guards.hasOwnKey(keptKeys, key)) {
            keptKeys[key] = true
            keptCount++
        }
    }
}

function memoSubset(source, keys, keptKeys) {
    var result = ({})
    for (var i = 0; i < keys.length; i++) {
        if (Guards.hasOwnKey(keptKeys, keys[i])) {
            result[keys[i]] = source[keys[i]]
        }
    }
    return result
}

function boundedMemo(memo, observations) {
    var source = copyMemo(memo)
    var keys = Object.keys(source)
    if (keys.length <= maximumMemoEntries) {
        return source
    }
    var keptKeys = ({})
    retainRecentKeys(keys, keptKeys, currentMemoKeys(observations))
    retainRecentKeys(keys, keptKeys, null)
    return memoSubset(source, keys, keptKeys)
}

// Missing rows are not evidence of recovery. Retain their bounded memo until
// they return; clear only the keys that this observation can rebuild.
function clearObservedRowState(nextMemo, observation) {
    var rows = Array.isArray(observation.rows) ? observation.rows : []
    for (var i = 0; i < rows.length; i++) {
        delete nextMemo[quotaKey(observation, rows[i], i)]
        delete nextMemo[resetKey(observation, rows[i], i)]
        delete nextMemo[paceKey(observation, rows[i], i)]
    }
}

function enabled(options, key) {
    return !options || options[key] !== false
}

function numericOption(options, key, fallback) {
    var value = Number(options && options[key])
    return isFinite(value) ? value : fallback
}

function plannerSettings(options) {
    var mode = options && options.mode ? String(options.mode) : "observe"
    return {
        mode: mode,
        priming: mode === "prime",
        statusEnabled: enabled(options, "statusEnabled"),
        quotaEnabled: enabled(options, "quotaEnabled"),
        paceEnabled: enabled(options, "paceEnabled"),
        resetEnabled: enabled(options, "resetEnabled"),
        resetArmThreshold: numericOption(options, "resetArmThreshold", 80),
        resetFloor: numericOption(options, "resetFloor", 5)
    }
}

function resetUsagePercent(row) {
    var used = Number(row && row.usedPercent)
    return row && row.hasPercent === true && isFinite(used) ? used : null
}

function primeRow(nextMemo, observation, index, settings) {
    var row = observation.rows[index]
    // A degraded first reading supplies no threshold baseline. Even a
    // healthy row below the warning level establishes one silently.
    if (row) {
        nextMemo[scopePrimedKey(observation)] = "1"
    }
    var level = quotaLevel(row, "")
    if (settings.quotaEnabled && level.length > 0) {
        nextMemo[quotaKey(observation, row, index)] = level
    }
    if (settings.paceEnabled && paceActive(row, false)) {
        nextMemo[paceKey(observation, row, index)] = "1"
    }
    if (settings.resetEnabled && resetDecision(row, false, settings).armed) {
        nextMemo[resetKey(observation, row, index)] = "1"
    }
}

function primeScope(nextMemo, observation, settings) {
    var rows = Array.isArray(observation.rows) ? observation.rows : []
    for (var i = 0; i < rows.length; i++) {
        if (!Normalizer.authoritativeQuota(rows[i])) {
            delete nextMemo[quotaKey(observation, rows[i], i)]
            delete nextMemo[paceKey(observation, rows[i], i)]
            delete nextMemo[resetKey(observation, rows[i], i)]
            continue
        }
        primeRow(nextMemo, observation, i, settings)
    }
}

function quotaLevel(row, previousLevel) {
    if (!Normalizer.authoritativeQuota(row)) {
        // Unverified usage cannot establish recovery from a notified quota.
        return previousLevel
    }
    var level = String(row && row.quotaLevel || "")
    if (level.length > 0) {
        return level
    }
    // An unreadable percentage is not a recovered one. Keep the previous
    // level so the next refresh cannot re-announce an unchanged condition.
    return row && row.hasPercent !== true ? previousLevel : ""
}

function processQuota(previousMemo, nextMemo, observation) {
    var intents = []
    var rows = Array.isArray(observation.rows) ? observation.rows : []
    for (var i = 0; i < rows.length; i++) {
        var key = quotaKey(observation, rows[i], i)
        var previousLevel = String(previousMemo && previousMemo[key] || "")
        var level = quotaLevel(rows[i], previousLevel)
        if (level.length > 0
                && NotificationMemo.severityRank(level) > NotificationMemo.severityRank(previousLevel)) {
            intents.push({kind: "quota", rowIndex: i, severity: level})
        }
        if (level.length > 0) {
            nextMemo[key] = level
        }
    }
    return intents
}

function paceActive(row, wasActive) {
    if (!Normalizer.authoritativeQuota(row)) {
        return wasActive
    }
    if (!row) {
        return false
    }
    if (row.paceActive === true) {
        return true
    }
    // Carry only an unavailable forecast. A known recovery clears the
    // baseline even when the usage percentage is unknown.
    return row.paceKnown !== true && wasActive
}

function processPace(previousMemo, nextMemo, observation) {
    var intents = []
    var rows = Array.isArray(observation.rows) ? observation.rows : []
    for (var i = 0; i < rows.length; i++) {
        var key = paceKey(observation, rows[i], i)
        var wasActive = !!previousMemo && previousMemo[key] === "1"
        if (!paceActive(rows[i], wasActive)) {
            continue
        }
        if (!wasActive) {
            intents.push({kind: "pace", rowIndex: i})
        }
        nextMemo[key] = "1"
    }
    return intents
}

function resetDecision(row, wasArmed, settings) {
    if (!Normalizer.authoritativeQuota(row)) {
        return {armed: false, notify: false}
    }
    var used = resetUsagePercent(row)
    if (used === null) {
        // An unreadable percentage is not a disarmed one. Keep the arm so
        // one degraded pass cannot swallow the promised reset notice.
        return {armed: wasArmed, notify: false}
    }
    if (wasArmed && used <= settings.resetFloor) {
        return {armed: false, notify: true}
    }
    return {
        armed: used >= settings.resetArmThreshold || (wasArmed && used > settings.resetFloor),
        notify: false
    }
}

function processReset(previousMemo, nextMemo, observation, settings) {
    var intents = []
    var rows = Array.isArray(observation.rows) ? observation.rows : []
    for (var i = 0; i < rows.length; i++) {
        var key = resetKey(observation, rows[i], i)
        var wasArmed = !!previousMemo && previousMemo[key] === "1"
        var decision = resetDecision(rows[i], wasArmed, settings)
        if (decision.notify) {
            intents.push({kind: "reset", rowIndex: i})
        } else if (decision.armed) {
            nextMemo[key] = "1"
        }
    }
    return intents
}

function statusAvailable(observation) {
    return observation.statusKnown !== false && observation.statusSeverity !== "unknown"
}

function processStatus(previousMemo, nextMemo, observation, settings) {
    if (!settings.statusEnabled || !statusAvailable(observation)) {
        if (settings.priming) {
            // Missing status cannot replace a baseline carried across a
            // settings change.
            NotificationMemo.carryStatusMemo(previousMemo, observation.providerID, nextMemo)
        }
        return []
    }
    var decision = NotificationMemo.statusDecision(previousMemo, observation.providerID,
        statusValue(observation), observation.statusSeverity)
    // Priming records the same decision silently, including a known
    // incident ID temporarily omitted by the status response.
    NotificationMemo.applyStatusDecision(nextMemo, observation.providerID, decision)
    if (settings.priming || !decision.notify) {
        return []
    }
    return [{kind: "status", severity: String(observation.statusSeverity || "")}]
}

function usageUnavailable(observation) {
    if (observation.usageStale === true) {
        return true
    }
    return observation.errorPresent === true
        && Array.isArray(observation.rows) && observation.rows.length === 0
}

function processUsage(previousMemo, nextMemo, observation, settings) {
    if (settings.priming) {
        primeScope(nextMemo, observation, settings)
        return []
    }
    clearObservedRowState(nextMemo, observation)
    if (!previousMemo || previousMemo[scopePrimedKey(observation)] !== "1") {
        primeScope(nextMemo, observation, settings)
        return []
    }
    var intents = []
    if (settings.quotaEnabled) {
        intents = intents.concat(processQuota(previousMemo, nextMemo, observation))
    }
    if (settings.paceEnabled) {
        intents = intents.concat(processPace(previousMemo, nextMemo, observation))
    }
    if (settings.resetEnabled) {
        intents = intents.concat(processReset(previousMemo, nextMemo, observation, settings))
    }
    return intents
}

function processObservation(previousMemo, nextMemo, observation, settings) {
    if (observation.pending === true) {
        if (settings.priming) {
            NotificationMemo.carryStatusMemo(previousMemo, observation.providerID, nextMemo)
        }
        return []
    }
    var intents = processStatus(previousMemo, nextMemo, observation, settings)
    // Status remains useful with stale quotas or a usage error. Neither can
    // rebuild threshold baselines; an unprimed scope must stay unprimed.
    if (usageUnavailable(observation)) {
        return intents
    }
    return intents.concat(processUsage(previousMemo, nextMemo, observation, settings))
}

function transition(observations, previousMemo, options) {
    var settings = plannerSettings(options)
    var items = Array.isArray(observations) ? observations : []
    if (settings.mode === "reset") {
        return {
            nextMemo: boundedMemo(
                NotificationMemo.preservedMemoAfterReset(previousMemo), []),
            intents: []
        }
    }
    var nextMemo = settings.priming ? ({}) : copyMemo(previousMemo)
    var intents = []
    for (var i = 0; i < items.length; i++) {
        if (!items[i]) {
            continue
        }
        var planned = processObservation(previousMemo, nextMemo, items[i], settings)
        for (var j = 0; j < planned.length; j++) {
            planned[j].observationIndex = i
            intents.push(planned[j])
        }
    }
    return { nextMemo: boundedMemo(nextMemo, items), intents: intents }
}
