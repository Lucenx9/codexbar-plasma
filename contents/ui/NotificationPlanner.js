.pragma library
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

function observationPending(refreshPending, errorPresent, incidentPresent, usageRowCount) {
    return refreshPending === true
        || (errorPresent === true
            && incidentPresent !== true
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
    return String(useResetTimestamp
        ? (row.resetsAt ? row.resetsAt : "")
        : (row.label ? row.label : ""))
}

// Occurrence ordinal among rows sharing the same lane and identity. Numbering
// duplicates instead of keying on the absolute index keeps baseline state
// stable when the CLI inserts or reorders unrelated usage windows.
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

function boundedMemo(memo, observations) {
    var source = copyMemo(memo)
    var keys = Object.keys(source)
    if (keys.length <= maximumMemoEntries) {
        return source
    }

    var protectedKeys = currentMemoKeys(observations)
    var keptKeys = ({})
    var keptCount = 0
    for (var i = keys.length - 1; i >= 0 && keptCount < maximumMemoEntries; i--) {
        if (Guards.hasOwnKey(protectedKeys, keys[i])) {
            keptKeys[keys[i]] = true
            keptCount++
        }
    }
    for (var j = keys.length - 1; j >= 0 && keptCount < maximumMemoEntries; j--) {
        if (!Guards.hasOwnKey(keptKeys, keys[j])) {
            keptKeys[keys[j]] = true
            keptCount++
        }
    }

    var result = ({})
    for (var k = 0; k < keys.length; k++) {
        if (Guards.hasOwnKey(keptKeys, keys[k])) {
            result[keys[k]] = source[keys[k]]
        }
    }
    return result
}

function clearScopeState(nextMemo, observation) {
    var scope = String(observation.scopeID || "")
    var quotaPrefix = "quota:" + scope + ":"
    var resetPrefix = "reset:" + scope + ":"
    var pacePrefix = "pace:" + scope + ":"
    for (var key in nextMemo) {
        if (!Guards.hasOwnKey(nextMemo, key)) {
            continue
        }
        if (key.indexOf(quotaPrefix) === 0
                || key.indexOf(resetPrefix) === 0
                || key.indexOf(pacePrefix) === 0) {
            delete nextMemo[key]
        }
    }
}

function primeScope(nextMemo, observation, options) {
    nextMemo[scopePrimedKey(observation)] = "1"
    if (!options || options.quotaEnabled !== false) {
        var rows = Array.isArray(observation.rows) ? observation.rows : []
        for (var i = 0; i < rows.length; i++) {
            var level = String(rows[i] && rows[i].quotaLevel || "")
            if (level.length > 0) {
                nextMemo[quotaKey(observation, rows[i], i)] = level
            }
        }
    }
    if (!options || options.paceEnabled !== false) {
        var paceRows = Array.isArray(observation.rows) ? observation.rows : []
        for (var paceIndex = 0; paceIndex < paceRows.length; paceIndex++) {
            if (paceRows[paceIndex] && paceRows[paceIndex].paceActive === true) {
                nextMemo[paceKey(observation, paceRows[paceIndex], paceIndex)] = "1"
            }
        }
    }
    if (!options || options.resetEnabled !== false) {
        var resetRows = Array.isArray(observation.rows) ? observation.rows : []
        var armThreshold = Number(options && options.resetArmThreshold)
        if (!isFinite(armThreshold)) {
            armThreshold = 80
        }
        for (var resetIndex = 0; resetIndex < resetRows.length; resetIndex++) {
            var row = resetRows[resetIndex]
            var used = Number(row && row.usedPercent)
            if (row && row.hasPercent === true && isFinite(used) && used >= armThreshold) {
                nextMemo[resetKey(observation, row, resetIndex)] = "1"
            }
        }
    }
}

function processQuota(previousMemo, nextMemo, observation, observationIndex, intents) {
    var rows = Array.isArray(observation.rows) ? observation.rows : []
    for (var i = 0; i < rows.length; i++) {
        var level = String(rows[i] && rows[i].quotaLevel || "")
        var key = quotaKey(observation, rows[i], i)
        var previousLevel = String(previousMemo && previousMemo[key] || "")
        if (level.length > 0
                && NotificationMemo.severityRank(level) > NotificationMemo.severityRank(previousLevel)) {
            intents.push({
                kind: "quota",
                observationIndex: observationIndex,
                rowIndex: i,
                severity: level
            })
        }
        if (level.length > 0) {
            nextMemo[key] = level
        } else if (rows[i] && rows[i].hasPercent !== true && previousLevel.length > 0) {
            // An unreadable percentage is not a recovered one. Carry the
            // previous level across the degraded pass so the next refresh
            // cannot re-announce an unchanged condition.
            nextMemo[key] = previousLevel
        }
    }
}

function processPace(previousMemo, nextMemo, observation, observationIndex, intents) {
    var rows = Array.isArray(observation.rows) ? observation.rows : []
    for (var i = 0; i < rows.length; i++) {
        var row = rows[i]
        var key = paceKey(observation, row, i)
        if (!row || row.paceActive !== true) {
            // Carry only an unavailable forecast. Pace remains authoritative
            // when usage percentage is unknown, so a valid recovery still
            // clears the active baseline.
            if (row && row.paceKnown !== true
                    && previousMemo && previousMemo[key] === "1") {
                nextMemo[key] = "1"
            }
            continue
        }
        if (!previousMemo || previousMemo[key] !== "1") {
            intents.push({
                kind: "pace",
                observationIndex: observationIndex,
                rowIndex: i
            })
        }
        nextMemo[key] = "1"
    }
}

function processReset(previousMemo, nextMemo, observation, observationIndex, options, intents) {
    var rows = Array.isArray(observation.rows) ? observation.rows : []
    var armThreshold = Number(options && options.resetArmThreshold)
    var floor = Number(options && options.resetFloor)
    if (!isFinite(armThreshold)) {
        armThreshold = 80
    }
    if (!isFinite(floor)) {
        floor = 5
    }
    for (var i = 0; i < rows.length; i++) {
        var row = rows[i]
        var key = resetKey(observation, row, i)
        var wasArmed = previousMemo && previousMemo[key] === "1"
        var used = Number(row && row.usedPercent)
        if (!row || row.hasPercent !== true || !isFinite(used)) {
            // An unreadable percentage is not a disarmed one. Keep the arm so
            // one degraded pass cannot swallow the promised reset notice.
            if (wasArmed) {
                nextMemo[key] = "1"
            }
            continue
        }
        if (wasArmed && used <= floor) {
            intents.push({
                kind: "reset",
                observationIndex: observationIndex,
                rowIndex: i
            })
        } else if (used >= armThreshold || (wasArmed && used > floor)) {
            nextMemo[key] = "1"
        }
    }
}

function transition(observations, previousMemo, options) {
    var mode = options && options.mode ? String(options.mode) : "observe"
    var items = Array.isArray(observations) ? observations : []
    if (mode === "reset") {
        return {
            nextMemo: boundedMemo(
                NotificationMemo.preservedMemoAfterReset(previousMemo), []),
            intents: []
        }
    }

    var nextMemo = mode === "prime" ? ({}) : copyMemo(previousMemo)
    var intents = []
    for (var i = 0; i < items.length; i++) {
        var item = items[i]
        if (!item) {
            continue
        }
        if (item.pending === true) {
            if (mode === "prime") {
                NotificationMemo.carryStatusMemo(previousMemo, item.providerID, nextMemo)
            }
            continue
        }
        if (!options || options.statusEnabled !== false) {
            var value = statusValue(item)
            if (mode === "prime") {
                NotificationMemo.applyStatusDecision(nextMemo, item.providerID,
                    ({ notify: false, value: value }))
            } else {
                var decision = NotificationMemo.statusDecision(
                    previousMemo,
                    item.providerID,
                    value,
                    item.statusSeverity)
                NotificationMemo.applyStatusDecision(nextMemo, item.providerID, decision)
                if (decision.notify) {
                    intents.push({
                        kind: "status",
                        observationIndex: i,
                        severity: String(item.statusSeverity || "")
                    })
                }
            }
        }
        if (mode === "prime") {
            if (item.errorPresent === true && Array.isArray(item.rows) && item.rows.length === 0) {
                // A failed first observation establishes no threshold
                // baseline: leave the scope unprimed so the first healthy
                // pass primes silently. The status block above already
                // recorded the incident, so it keeps notifying later.
                continue
            }
            primeScope(nextMemo, item, options)
            continue
        }
        // An error observation with no usage rows carries no threshold
        // evidence: keep quota/pace/reset state untouched instead of treating
        // the outage as a quiet recovery, and leave an unprimed scope
        // unprimed so the next healthy pass primes silently. Status above has
        // already processed, so incidents keep notifying through the outage.
        if (item.errorPresent === true && Array.isArray(item.rows) && item.rows.length === 0) {
            continue
        }
        clearScopeState(nextMemo, item)
        if (!previousMemo || previousMemo[scopePrimedKey(item)] !== "1") {
            primeScope(nextMemo, item, options)
            continue
        }
        if (!options || options.quotaEnabled !== false) {
            processQuota(previousMemo, nextMemo, item, i, intents)
        }
        if (!options || options.paceEnabled !== false) {
            processPace(previousMemo, nextMemo, item, i, intents)
        }
        if (!options || options.resetEnabled !== false) {
            processReset(previousMemo, nextMemo, item, i, options, intents)
        }
    }
    return { nextMemo: boundedMemo(nextMemo, items), intents: intents }
}
