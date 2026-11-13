.pragma library
.import "Guards.mjs" as Core

// Keep the shared QML guard entry point; workers import the same implementation.
var hasOwnKey = Core.hasOwnKey
var isRecord = Core.isRecord
var isFiniteNumber = Core.isFiniteNumber
var isNonNegativeInteger = Core.isNonNegativeInteger
var isArrayIndex = Core.isArrayIndex
var isUnsafeObjectKey = Core.isUnsafeObjectKey
var copyObject = Core.copyObject
var shellQuote = Core.shellQuote
var boundedShellCommand = Core.boundedShellCommand
var commandNotFoundExitCode = Core.commandNotFoundExitCode
var commandNotExecutableExitCode = Core.commandNotExecutableExitCode
var exitCode = Core.exitCode
var isCommandPathFailure = Core.isCommandPathFailure
var supervisedShellCommand = Core.supervisedShellCommand
