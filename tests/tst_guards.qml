import QtQuick
import QtTest
import "../contents/ui/Guards.js" as Guards

TestCase {
    name: "Guards"

    function test_hasOwnKeyFindsOwnPropertiesOnly() {
        var item = { present: 1, falsy: 0, empty: "" }
        verify(Guards.hasOwnKey(item, "present"))
        verify(Guards.hasOwnKey(item, "falsy"))
        verify(Guards.hasOwnKey(item, "empty"))
        verify(!Guards.hasOwnKey(item, "absent"))
    }

    function test_hasOwnKeyIgnoresInheritedProperties() {
        verify(!Guards.hasOwnKey({}, "toString"))
        verify(!Guards.hasOwnKey({}, "constructor"))
        verify(!Guards.hasOwnKey({}, "hasOwnProperty"))
    }

    // The reason the check goes through Object.prototype: a CLI payload can
    // carry its own `hasOwnProperty` and would otherwise answer for itself.
    function test_hasOwnKeySurvivesAPayloadThatShadowsHasOwnProperty() {
        var hostile = JSON.parse('{"hasOwnProperty": "not a function", "real": 1}')
        verify(Guards.hasOwnKey(hostile, "real"))
        verify(!Guards.hasOwnKey(hostile, "absent"))
    }

    function test_hasOwnKeyRefusesAbsentContainers() {
        verify(!Guards.hasOwnKey(null, "a"))
        verify(!Guards.hasOwnKey(undefined, "a"))
        verify(!Guards.hasOwnKey("", "a"))
    }

    function test_isUnsafeObjectKeyRejectsThePrototypeSlots() {
        verify(Guards.isUnsafeObjectKey("__proto__"))
        verify(Guards.isUnsafeObjectKey("constructor"))
        verify(Guards.isUnsafeObjectKey("prototype"))
    }

    function test_isUnsafeObjectKeyAcceptsOrdinaryKeys() {
        verify(!Guards.isUnsafeObjectKey("codex"))
        verify(!Guards.isUnsafeObjectKey("2026-08-19"))
        verify(!Guards.isUnsafeObjectKey(""))
        verify(!Guards.isUnsafeObjectKey(null))
        verify(!Guards.isUnsafeObjectKey(undefined))
    }

    // A non-string key reaches the same slot once JavaScript coerces it, so the
    // check has to coerce first rather than compare the raw value.
    function test_isUnsafeObjectKeyCoercesBeforeComparing() {
        var stringifies = { toString: function() { return "__proto__" } }
        verify(Guards.isUnsafeObjectKey(stringifies))
        verify(Guards.isUnsafeObjectKey(["__proto__"]))
    }

    function test_copyObjectKeepsOwnEntries() {
        var copy = Guards.copyObject({ a: 1, b: "two" })
        compare(copy.a, 1)
        compare(copy.b, "two")
    }

    function test_copyObjectReturnsANewObject() {
        var original = { a: 1 }
        var copy = Guards.copyObject(original)
        copy.a = 2
        compare(original.a, 1)
    }

    function test_copyObjectDropsPrototypePollutingKeys() {
        var hostile = JSON.parse('{"__proto__": {"polluted": true}, "constructor": 1, "prototype": 2, "keep": 3}')
        var copy = Guards.copyObject(hostile)
        compare(copy.keep, 3)
        verify(!Guards.hasOwnKey(copy, "__proto__"))
        verify(!Guards.hasOwnKey(copy, "constructor"))
        verify(!Guards.hasOwnKey(copy, "prototype"))
        compare(({}).polluted, undefined)
    }

    function test_copyObjectSurvivesAbsentInput() {
        compare(JSON.stringify(Guards.copyObject(null)), "{}")
        compare(JSON.stringify(Guards.copyObject(undefined)), "{}")
    }

    function test_shellQuoteWrapsTheWholeValue() {
        compare(Guards.shellQuote("codex"), "'codex'")
        compare(Guards.shellQuote(""), "''")
    }

    function test_shellQuoteEscapesEmbeddedSingleQuotes() {
        compare(Guards.shellQuote("it's"), "'it'\\''s'")
    }

    // Everything below is inert inside single quotes; this is why a
    // CLI-controlled label cannot grow into a second command.
    function test_shellQuoteNeutralisesCommandInjection() {
        compare(Guards.shellQuote("; rm -rf /"), "'; rm -rf /'")
        compare(Guards.shellQuote("$(whoami)"), "'$(whoami)'")
        compare(Guards.shellQuote("`id`"), "'`id`'")
        compare(Guards.shellQuote("a && b"), "'a && b'")
        compare(Guards.shellQuote("$HOME"), "'$HOME'")
    }

    // The break-out attempt: close the quote, run a command, reopen. Each quote
    // has to come back escaped or the payload becomes a command.
    function test_shellQuoteResistsAQuoteBreakout() {
        compare(Guards.shellQuote("'; id; '"), "''\\''; id; '\\'''")
    }

    function test_shellQuoteCoercesNonStrings() {
        compare(Guards.shellQuote(7), "'7'")
        compare(Guards.shellQuote(null), "'null'")
    }
}
