import QtQuick
import QtTest
import "../contents/ui/ProviderRosterCache.js" as ProviderRosterCache

TestCase {
    name: "ProviderRosterCache"

    function context(commandSource, revision, stamp) {
        return {
            commandSource: commandSource === undefined
                ? "codexbar config providers --format json --json-only"
                : commandSource,
            revision: revision === undefined ? 7 : revision,
            stamp: stamp === undefined ? "12345 678 config.json" : stamp
        }
    }

    function test_exactContextReturnsADefensiveCopy() {
        var cache = ProviderRosterCache.remember(["codex", "claude"], context())
        var providerIDs = ProviderRosterCache.read(cache, context())

        compare(providerIDs.length, 2)
        compare(providerIDs[0], "codex")
        providerIDs.push("gemini")
        compare(ProviderRosterCache.read(cache, context()).length, 2)
    }

    function test_commandRevisionAndChecksumMismatchesMiss() {
        var cache = ProviderRosterCache.remember(["codex"], context())

        compare(ProviderRosterCache.read(cache, context("other", 7)), null)
        compare(ProviderRosterCache.read(cache, context(undefined, 8)), null)
        compare(ProviderRosterCache.read(cache, context(undefined, 7, "different")), null)
    }

    function test_emptyRosterIsACacheableSuccess() {
        var cache = ProviderRosterCache.remember([], context())
        var providerIDs = ProviderRosterCache.read(cache, context())

        verify(Array.isArray(providerIDs))
        compare(providerIDs.length, 0)
    }

    function test_rejectsProviderIDsOutsideTheNormalizedContract() {
        var tooLong = Array(130).join("a")
        var invalidRosters = [
            [" codex "],
            ["Codex"],
            ["groqcloud"],
            ["codex", "codex"],
            ["__proto__"],
            [tooLong]
        ]

        for (var i = 0; i < invalidRosters.length; i++) {
            compare(ProviderRosterCache.remember(invalidRosters[i], context()), null)
        }
    }

    function test_rejectsRostersAboveTheProviderSnapshotBound() {
        var providerIDs = []
        for (var i = 0; i < 257; i++) {
            providerIDs.push("future-provider-" + i)
        }

        compare(ProviderRosterCache.remember(providerIDs, context()), null)
    }

    function test_readRejectsAMutatedRoster() {
        var cache = ProviderRosterCache.remember(["codex"], context())
        cache.providerIDs.push(" groq ")

        compare(ProviderRosterCache.read(cache, context()), null)
    }

    function test_unknownChecksumNeverCreatesAReusableCache() {
        compare(ProviderRosterCache.remember(["codex"], context(undefined, 7, "")), null)
        compare(ProviderRosterCache.read({
            context: context(undefined, 7, ""),
            providerIDs: ["codex"]
        }, context(undefined, 7, "")), null)
    }

    function test_responseContextAcceptsMatchingUnknownChecksums() {
        compare(ProviderRosterCache.responseContextsMatch(
            context(undefined, 7, ""), context(undefined, 7, "")), true)
        compare(ProviderRosterCache.responseContextsMatch(
            context(undefined, 7, ""), context(undefined, 8, "")), false)
        compare(ProviderRosterCache.responseContextsMatch(
            context(undefined, 7, ""), context(undefined, 7, "known")), false)
    }

    function test_contextMatchRejectsMalformedAndInheritedRecords() {
        compare(ProviderRosterCache.contextsMatch(context(), context()), true)
        compare(ProviderRosterCache.contextsMatch(null, context()), false)

        var inherited = Object.create(context())
        compare(ProviderRosterCache.contextsMatch(inherited, context()), false)
    }
}
