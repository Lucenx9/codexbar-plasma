.pragma library

// QNetworkInformation::Reachability. The applet reads it through an optional
// QtNetwork loader; a missing module or backend stays unknown.
var unknown = 0
var disconnected = 1
var local = 2
var site = 3
var online = 4

// The released CLI (0.79.0) reports transport failures as free provider text
// with kind "provider". Until it classifies them, recognize only Foundation
// URL error codes and the DNS failure its providers pass through offline.
// This adds a localized headline; the CLI text itself is never translated.
var timeoutCodes = ["-1001"]
var offlineCodes = ["-1003", "-1004", "-1005", "-1009", "-1018", "-1020"]

function isOffline(reachability) {
    return reachability === disconnected || reachability === local
}

// Only a return to a full internet route counts: startup (unknown) and an
// intranet-only route must not start a refresh on their own.
function reconnected(previous, current) {
    return isOffline(previous) && current === online
}

function messageKind(message) {
    if (typeof message !== "string" || message.length === 0)
        return ""
    var code = /NSURLErrorDomain\D{0,12}(-\d+)/.exec(message)
    if (code && timeoutCodes.indexOf(code[1]) !== -1)
        return "timeout"
    if (code && offlineCodes.indexOf(code[1]) !== -1)
        return "offline"
    return /could not resolve host/i.test(message) ? "offline" : ""
}

// Returns "offline", "timeout" or "" for a provider error message. A network
// failure while the system reports no internet route is the connection.
function errorKind(message, reachability) {
    var kind = messageKind(message)
    return kind.length > 0 && isOffline(reachability) ? "offline" : kind
}
