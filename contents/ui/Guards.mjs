
// The guards every surface needs before it touches CLI-controlled data.
//
// QML and JS files share no function scope, so each file that calls one of
// these unqualified still has to declare the name. What it no longer has to
// carry is the body: a declaration here is a one-line delegation, so the
// prototype-pollution guard and the shell-quoting rule exist once and are tested
// once, instead of being copied into four or five files and asserted by
// searching each copy for the right fragment.
//
// `scripts/test_security_regressions.sh` still requires the declaration in every
// calling file through `require_definition_where_used`; the fragment it pins is
// now the delegation rather than a repeated guard.

// Own properties only, read through `Object.prototype` so a payload carrying its
// own `hasOwnProperty` key cannot answer for itself.
export function hasOwnKey(item, key) {
    return item ? Object.prototype.hasOwnProperty.call(item, key) : false
}

export function isRecord(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
}

export function isFiniteNumber(value) {
    return typeof value === "number" && isFinite(value)
}

export function isNonNegativeInteger(value) {
    return isFiniteNumber(value) && Math.floor(value) === value && value >= 0
}

export function isArrayIndex(items, index) {
    return Array.isArray(items) && typeof index === "number"
        && Math.floor(index) === index && index >= 0 && index < items.length
}

// The key is coerced first: a non-string key that stringifies to `__proto__`
// reaches the same slot as the string would.
export function isUnsafeObjectKey(key) {
    var value = String(key || "")
    return value === "__proto__" || value === "constructor" || value === "prototype"
}

export function copyObject(item) {
    var copy = ({})
    for (var key in item) {
        if (!hasOwnKey(item, key) || isUnsafeObjectKey(key)) {
            continue
        }
        copy[key] = item[key]
    }
    return copy
}

// Single-quote the whole value and close, escape, reopen around each embedded
// quote. Inside single quotes a POSIX shell expands nothing, so this is the only
// escaping the value needs, and it is the reason no CLI-controlled string can
// grow into a second command.
export function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
}

// Wrap a command so the shell kills a hung child on schedule; disconnectSource
// cannot. When GNU timeout is absent the raw command runs instead, so callers
// keep working without coreutils. `sh -c` carries the conditional because a
// run-nonce prefix (`NAME=value` assignment) is only valid before a simple
// command, not before `if`.
// `--foreground` keeps the bound silent: without it, a `--kill-after`
// escalation SIGKILLs timeout's process group including timeout itself, and
// any shell reaping that signalled child may announce it with `Killed` on
// stderr, which would outrank the caller's timeout message. In the foreground
// the signals go to the hung child only, timeout exits 124/137 normally, and
// stderr stays empty so the CLI's own error text still flows through.
// Callers that can spawn descendants opt into a process-group timeout instead.
// Keep that monitor behind a waiting shell so destroying the engine-owned
// shell cannot remove the bound. Its monitored shell must survive TERM until
// the kill escalation, even if the direct child exits before its descendants.
// Catch PIPE only in that shell: a diagnostic on a disconnected engine pipe
// must not cancel the escalation. Caught handlers reset in executed children.
// These callers place the bound after their UI deadline.
export function boundedShellCommand(command, timeoutSeconds, killAfterSeconds, processGroup) {
    if (command.length === 0) {
        return ""
    }
    var monitored = processGroup === true
        ? "sh -c " + shellQuote("trap 'while :; do sleep 1; done' TERM; trap ':' PIPE; " + command)
        : command
    var bounded = "timeout " + (processGroup === true ? "" : "--foreground ")
        + "--kill-after=" + shellQuote(killAfterSeconds + "s")
        + " " + shellQuote(timeoutSeconds + "s")
        + " " + monitored
    var script = "if command -v timeout >/dev/null 2>&1 && timeout --foreground --kill-after=1s 1s true >/dev/null 2>&1; then "
        + bounded + (processGroup === true ? " & wait $!" : "")
        + "; else " + command + "; fi"
    return "sh -c " + shellQuote(script)
}

// POSIX shells report 127 for a command that could not be found and 126 for one
// that exists but could not be executed. Both mean the configured command path
// is wrong, which needs a different answer from a provider or network failure.
// The codes are part of the shell contract, so they hold in every locale, while
// the matching stderr text does not.
export var commandNotFoundExitCode = 127
export var commandNotExecutableExitCode = 126

// The numeric exit status, or NaN when the engine reported none. A missing or
// malformed status is a failure, never an implicit 0.
export function exitCode(value) {
    if (typeof value === "number") {
        return value
    }
    return typeof value === "string" && /^\s*-?\d+\s*$/.test(value) ? Number(value) : Number.NaN
}

export function isCommandPathFailure(exitCode) {
    // The engine reports the code as a number or a string. Anything else,
    // including a single-element array that would coerce to 127, is not an
    // exit code and must not be read as one.
    if (typeof exitCode !== "number" && typeof exitCode !== "string") {
        return false
    }
    var code = Number(exitCode)
    return isFinite(code)
        && (code === commandNotFoundExitCode || code === commandNotExecutableExitCode)
}

// A direct timeout parent lets the helper detect engine process destruction.
// Disconnect alone may retain a cached engine source, so login also has an
// explicit cancellation request owned by the page.
export function supervisedShellCommand(command, timeoutSeconds, killAfterSeconds) {
    return "sh -c " + shellQuote("exec timeout --kill-after="
        + shellQuote(killAfterSeconds + "s") + " " + shellQuote(timeoutSeconds + "s") + " " + command)
}
