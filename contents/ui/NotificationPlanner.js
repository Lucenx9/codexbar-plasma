.pragma library
.import "Guards.js" as Guards
.import "NotificationMemo.js" as NotificationMemo

// Pure transition kernel for provider notifications. Callers supply normalized
// observations and keep ownership of localization, timers, refresh lifecycle,
// and notification effects. The memo is opaque outside this module: callers
// only retain `nextMemo` and feed it into the next transition.

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
        }
    }
}

function processPace(previousMemo, nextMemo, observation, observationIndex, intents) {
    var rows = Array.isArray(observation.rows) ? observation.rows : []
    for (var i = 0; i < rows.length; i++) {
        if (!rows[i] || rows[i].paceActive !== true) {
            continue
        }
        var key = paceKey(observation, rows[i], i)
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
        var used = Number(row && row.usedPercent)
        if (!row || row.hasPercent !== true || !isFinite(used)) {
            continue
        }
        var key = resetKey(observation, row, i)
        var wasArmed = previousMemo && previousMemo[key] === "1"
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
            nextMemo: NotificationMemo.preservedMemoAfterReset(previousMemo),
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
            primeScope(nextMemo, item, options)
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
    return { nextMemo: nextMemo, intents: intents }
}
