.pragma library
.import "Guards.js" as Guards

// The ledger of external commands a QML surface has started and not yet retired.
//
// One map, keyed by the source name Plasma hands back on every reply, holds
// everything the caller needs to know about a running command: its kind and
// deadline plus any caller-specific context.
//
// That map is the only record. Routing reads the entry for a returned source
// name, so a reply is delivered while the ledger still holds it and dropped when
// it does not.
//
// That is also the staleness rule. Starting a newer command retires the older
// source name first, so a late reply from the retired one is no longer in the
// ledger and cannot overwrite the fresher result.
//
// Like ProviderNormalizer.js this module must not reach for `Qt`, `Kirigami`, or
// `i18n`, and it never mutates the map it is given: every change returns a new
// map so QML property bindings on command ledgers re-evaluate.

function hasOwnKey(item, key) {
    return Guards.hasOwnKey(item, key)
}

function isUnsafeObjectKey(key) {
    return Guards.isUnsafeObjectKey(key)
}

function copyCommands(commands) {
    var copy = ({})
    for (var key in commands) {
        if (hasOwnKey(commands, key) && !isUnsafeObjectKey(key)) {
            copy[key] = commands[key]
        }
    }
    return copy
}

// Every command carries a per-run nonce so Plasma treats each start as a new
// source and a late reply from a previous run arrives under a name the ledger
// has already dropped. The caller owns the serial, because incrementing it is
// the side effect this module does not take.
function withRunNonce(command, serial) {
    if (!command || String(command).length === 0) {
        return ""
    }
    return "CODEXBAR_PLASMA_RUN=" + serial + " " + command
}

// `timeoutMs` falls back to `fallbackTimeoutMs` when it is missing or not a
// positive number, so a caller cannot accidentally register a command that never
// expires. When the fallback is unusable too, a 1ms timeout fails closed
// instead of minting a NaN deadline: NaN disables the timeout timer
// (hasDeadlines) while expired() skips it for ever, leaking the entry.
function descriptor(kind, providerID, nowMs, timeoutMs, fallbackTimeoutMs) {
    var boundedTimeout = Number(timeoutMs)
    if (!isFinite(boundedTimeout) || boundedTimeout <= 0) {
        boundedTimeout = Number(fallbackTimeoutMs)
    }
    if (!isFinite(boundedTimeout) || boundedTimeout <= 0) {
        boundedTimeout = 1
    }
    var now = Number(nowMs)
    if (!isFinite(now) || now < 0) {
        now = 0
    }
    return {
        kind: String(kind || ""),
        providerID: String(providerID || ""),
        deadlineMs: now + boundedTimeout
    }
}

// A command with no descriptor still gets an entry, so an unrouted reply can be
// recognised and disconnected instead of leaking a live source.
function opened(commands, sourceName, entry) {
    var next = copyCommands(commands)
    if (!sourceName || sourceName.length === 0 || isUnsafeObjectKey(sourceName)) {
        return next
    }
    next[sourceName] = entry || { kind: "", providerID: "", deadlineMs: 0 }
    return next
}

function closed(commands, sourceName) {
    var next = copyCommands(commands)
    delete next[sourceName]
    return next
}

function find(commands, sourceName) {
    if (!sourceName || !hasOwnKey(commands, sourceName)) {
        return null
    }
    return commands[sourceName] || null
}

function sourcesOfKind(commands, kind) {
    var names = []
    for (var sourceName in commands) {
        if (!hasOwnKey(commands, sourceName)) {
            continue
        }
        var entry = commands[sourceName]
        if (entry && String(entry.kind || "") === kind) {
            names.push(sourceName)
        }
    }
    return names
}

function hasKind(commands, kind) {
    return sourcesOfKind(commands, kind).length > 0
}

function hasAnyKind(commands, kinds) {
    if (!Array.isArray(kinds) || kinds.length === 0) {
        return false
    }
    for (var sourceName in commands) {
        if (!hasOwnKey(commands, sourceName)) {
            continue
        }
        var entry = commands[sourceName]
        if (entry && kinds.indexOf(String(entry.kind || "")) >= 0) {
            return true
        }
    }
    return false
}

// Drives the timeout timer. A zero or absent deadline means the command is
// waited on without a clock, so it must not keep the timer running.
function hasDeadlines(commands) {
    for (var sourceName in commands) {
        if (!hasOwnKey(commands, sourceName)) {
            continue
        }
        var entry = commands[sourceName]
        if (entry && Number(entry.deadlineMs) > 0) {
            return true
        }
    }
    return false
}

function expired(commands, nowMs) {
    var overdue = []
    for (var sourceName in commands) {
        if (!hasOwnKey(commands, sourceName)) {
            continue
        }
        var entry = commands[sourceName]
        var deadline = entry ? Number(entry.deadlineMs) : 0
        if (!isFinite(deadline) || deadline <= 0 || nowMs < deadline) {
            continue
        }
        overdue.push({ sourceName: sourceName, descriptor: entry })
    }
    return overdue
}
