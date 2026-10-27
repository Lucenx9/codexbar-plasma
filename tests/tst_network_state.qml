import QtQuick
import QtTest
import "../contents/ui/NetworkState.js" as NetworkState

TestCase {
    name: "NetworkState"

    // QNetworkInformation::Reachability values, written out independently.
    readonly property int unknown: 0
    readonly property int disconnected: 1
    readonly property int local: 2
    readonly property int site: 3
    readonly property int online: 4

    function test_errorKind_data() {
        return [
            {tag: "codex timeout", message: "Network error: The operation could not be completed. (NSURLErrorDomain error -1001.)", kind: "timeout"},
            {tag: "error domain timeout", message: "Error Domain=NSURLErrorDomain Code=-1001 \"(null)\"", kind: "timeout"},
            {tag: "english prose is not parsed", message: "Claude API usage network error: The request timed out.", kind: ""},
            {tag: "not connected", message: "Network error: The operation could not be completed. (NSURLErrorDomain error -1009.)", kind: "offline"},
            {tag: "cannot find host", message: "Kimi network error: (NSURLErrorDomain error -1003.)", kind: "offline"},
            {tag: "cannot connect", message: "Error Domain=NSURLErrorDomain Code=-1004", kind: "offline"},
            {tag: "connection lost", message: "Network error: (NSURLErrorDomain error -1005.)", kind: "offline"},
            {tag: "dns via curl", message: "Network error: Could not resolve host: chatgpt.com", kind: "offline"},
            {tag: "longer code is not a timeout", message: "(NSURLErrorDomain error -10010.)", kind: ""},
            {tag: "bad server response", message: "Network error: (NSURLErrorDomain error -1011.)", kind: ""},
            {tag: "authentication", message: "Codex OAuth token expired or invalid. Run `codex login` to re-authenticate.", kind: ""},
            {tag: "server error", message: "Codex API error 503.", kind: ""},
            {tag: "unrelated timeout", message: "codexbar command timed out.", kind: ""},
            {tag: "empty", message: "", kind: ""},
            {tag: "null", message: null, kind: ""},
            {tag: "undefined", message: undefined, kind: ""},
            {tag: "number", message: -1001, kind: ""},
            {tag: "object", message: {message: "NSURLErrorDomain error -1009"}, kind: ""}
        ]
    }

    function test_errorKind(data) {
        compare(NetworkState.errorKind(data.message, online), data.kind)
        compare(NetworkState.errorKind(data.message, unknown), data.kind)
    }

    // A request that timed out while the system has no internet route is the
    // missing connection, not a slow server.
    function test_offlineSystemTurnsNetworkTimeoutsIntoOffline() {
        var timeout = "Network error: (NSURLErrorDomain error -1001.)"
        compare(NetworkState.errorKind(timeout, disconnected), "offline")
        compare(NetworkState.errorKind(timeout, local), "offline")
        compare(NetworkState.errorKind(timeout, site), "timeout")
    }

    // Local sources still answer offline, so a provider failure that does not
    // look like a network error keeps its own meaning.
    function test_offlineSystemKeepsOtherErrorsUnclassified() {
        compare(NetworkState.errorKind("Codex API error 401.", disconnected), "")
        compare(NetworkState.errorKind("", disconnected), "")
    }

    function test_isOffline() {
        verify(NetworkState.isOffline(disconnected))
        verify(NetworkState.isOffline(local))
        for (var value of [unknown, site, online, undefined, null, "1", NaN, 99])
            verify(!NetworkState.isOffline(value), String(value))
    }

    function test_reconnected() {
        verify(NetworkState.reconnected(disconnected, online))
        verify(NetworkState.reconnected(local, online))
        // Startup and backend changes are not a recovered connection.
        verify(!NetworkState.reconnected(unknown, online))
        verify(!NetworkState.reconnected(online, online))
        verify(!NetworkState.reconnected(site, online))
        verify(!NetworkState.reconnected(disconnected, local))
        verify(!NetworkState.reconnected(disconnected, unknown))
        verify(!NetworkState.reconnected(disconnected, "4"))
    }
}
