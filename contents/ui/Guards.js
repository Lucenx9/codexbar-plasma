.pragma library
.import "Guards.mjs" as Core

// Keep the shared QML guard entry point; workers import the same implementation.
// Explicit functions keep this compatibility entry point visible to qmllint.
function hasOwnKey(item, key) {
    return Core.hasOwnKey(item, key)
}
function isRecord(value) {
    return Core.isRecord(value)
}
function isFiniteNumber(value) {
    return Core.isFiniteNumber(value)
}
function isNonNegativeInteger(value) {
    return Core.isNonNegativeInteger(value)
}
function isArrayIndex(items, index) {
    return Core.isArrayIndex(items, index)
}
function isUnsafeObjectKey(key) {
    return Core.isUnsafeObjectKey(key)
}
function copyObject(item) {
    return Core.copyObject(item)
}
function shellQuote(value) {
    return Core.shellQuote(value)
}
function boundedShellCommand(command, timeoutSeconds, killAfterSeconds, processGroup) {
    return Core.boundedShellCommand(command, timeoutSeconds, killAfterSeconds, processGroup)
}
var commandNotFoundExitCode = Core.commandNotFoundExitCode
var commandNotExecutableExitCode = Core.commandNotExecutableExitCode
function exitCode(value) {
    return Core.exitCode(value)
}
function isCommandPathFailure(exitCode) {
    return Core.isCommandPathFailure(exitCode)
}
function supervisedShellCommand(command, timeoutSeconds, killAfterSeconds) {
    return Core.supervisedShellCommand(command, timeoutSeconds, killAfterSeconds)
}
