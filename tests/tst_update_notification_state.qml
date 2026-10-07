import QtQuick
import QtTest
import "../contents/ui/UpdateNotificationState.js" as State

TestCase {
    name: "UpdateNotificationState"

    function test_releaseUrl_data() {
        return [
            {tag: "official", input: "https://github.com/steipete/CodexBar/releases/tag/v1", expected: "https://github.com/steipete/CodexBar/releases/tag/v1"},
            {tag: "trim", input: " https://github.com/a/b ", expected: "https://github.com/a/b"},
            {tag: "http", input: "http://github.com/a", expected: ""},
            {tag: "foreign", input: "https://github.com.example.org/a", expected: ""},
            {tag: "credentials", input: "https://user@github.com/a", expected: ""},
            {tag: "script", input: "javascript:alert(1)", expected: ""},
            {tag: "oversized", input: "https://github.com/" + "a".repeat(2048), expected: ""},
            {tag: "null", input: null, expected: ""},
            {tag: "object", input: {url: "https://github.com/a"}, expected: ""}
        ]
    }
    function test_releaseUrl(data) { compare(State.safeReleaseUrl(data.input), data.expected) }

    function test_widgetVersionAndAssetFallback() {
        compare(State.widgetCandidate(" v1 ", "asset", ""), {version: "v1", memoKey: "v1"})
        compare(State.widgetCandidate("v1", "asset", "v1"), null)
        compare(State.widgetCandidate("", "asset", ""), {version: "", memoKey: "asset"})
        compare(State.widgetCandidate("", "asset", "asset"), null)
        compare(State.widgetCandidate("", "", ""), null)
    }
    function test_actionSourcesAreIndependentAndConsumedOnce() {
        var firstUrl = "https://github.com/a/releases/1"
        var secondUrl = "https://github.com/b/releases/2"
        var original = {first: firstUrl}
        var pending = State.register(original, "second", secondUrl)
        compare(original, {first: firstUrl})
        var activated = State.consume(pending, "second")
        compare(activated.releaseUrl, secondUrl)
        compare(activated.nextPending, original)
        compare(pending.second, secondUrl)
        compare(State.consume(activated.nextPending, "second").releaseUrl, "")
        compare(State.consume(activated.nextPending, "first").releaseUrl, firstUrl)
    }
    function test_untrustedSourcesAndUrlsNeverBecomeActions() {
        var inherited = Object.create({ghost: "https://github.com/a"})
        for (var source of ["", "__proto__", "constructor", "prototype", null, 123]) {
            compare(State.register(({}), source, "https://github.com/a"), ({}))
            compare(State.consume(inherited, source).releaseUrl, "")
        }
        compare(State.consume(inherited, "ghost").releaseUrl, "")
        compare(State.register(({}), "first", "https://example.org/a"), ({}))
        var invalid = State.consume({first: "javascript:alert(1)"}, "first")
        compare(invalid, {nextPending: ({}), releaseUrl: ""})
    }
}
