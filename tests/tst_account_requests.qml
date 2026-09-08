import QtQuick
import QtTest
import "../contents/ui/AccountRequests.js" as AccountRequests
import "../contents/ui/CommandLedger.js" as CommandLedger

TestCase {
    name: "AccountRequests"

    function start(commands, sourceName, providerID, signature) {
        var descriptor = CommandLedger.descriptor("account", providerID, 1000, 60000, 60000);
        descriptor.commandSignature = signature;
        return CommandLedger.opened(commands, sourceName, descriptor);
    }

    function test_loadingBelongsToTheRegisteredProviderRequest() {
        var commands = start(({}), "run-1", "codex", "accounts-context-a");
        verify(AccountRequests.isLoading(commands, "codex"));
        verify(!AccountRequests.isLoading(commands, "claude"));
        commands = CommandLedger.closed(commands, "run-1");
        verify(!AccountRequests.isLoading(commands, "codex"));
    }

    function test_currentReplyCanPublishAccountDataAndReleaseLoading() {
        var commands = start(({}), "run-1", "codex", "accounts-context-a");
        var decision = AccountRequests.completion(commands, "run-1", "accounts-context-a");
        compare(decision.providerID, "codex");
        verify(decision.acceptsPayload);
        // QML applies the completion by disconnecting and closing the source.
        commands = CommandLedger.closed(commands, "run-1");
        verify(!AccountRequests.isLoading(commands, "codex"));
    }

    function test_missingSignaturesNeverAuthorizePayloads() {
        var commands = start(({}), "run-1", "codex", undefined);
        verify(!AccountRequests.completion(commands, "run-1", undefined).acceptsPayload);
        commands = start(({}), "run-2", "codex", "");
        verify(!AccountRequests.completion(commands, "run-2", "").acceptsPayload);
    }

    function test_obsoleteContextFinishesWithoutPublishingAndAllowsAnotherLoad() {
        var commands = start(({}), "run-1", "codex", "accounts-context-a");
        var decision = AccountRequests.completion(commands, "run-1", "accounts-context-b");
        verify(decision !== null);
        verify(!decision.acceptsPayload);
        compare(decision.providerID, "codex");
        commands = CommandLedger.closed(commands, "run-1");
        verify(!AccountRequests.isLoading(commands, "codex"));

        commands = start(commands, "run-2", "codex", "accounts-context-b");
        verify(AccountRequests.isLoading(commands, "codex"));
        verify(AccountRequests.completion(commands, "run-2", "accounts-context-b").acceptsPayload);
    }

    function test_retiredReplyCannotCompleteTheReplacementRequest() {
        var commands = start(({}), "run-1", "codex", "accounts-context-a");
        commands = CommandLedger.closed(commands, "run-1");
        commands = start(commands, "run-2", "codex", "accounts-context-a");
        compare(AccountRequests.completion(commands, "run-1", "accounts-context-a"), null);
        verify(AccountRequests.isLoading(commands, "codex"));
        verify(AccountRequests.completion(commands, "run-2", "accounts-context-a").acceptsPayload);
    }

    function test_retiringObsoleteContextKeepsOtherRegisteredLoads() {
        var commands = start(({}), "run-1", "codex", "accounts-context-a");
        commands = start(commands, "run-2", "codex", "accounts-context-b");
        commands = start(commands, "run-3", "claude", "claude-context");
        verify(!AccountRequests.completion(commands, "run-1", "accounts-context-b").acceptsPayload);
        commands = CommandLedger.closed(commands, "run-1");
        verify(AccountRequests.isLoading(commands, "codex"));
        verify(AccountRequests.isLoading(commands, "claude"));
        commands = CommandLedger.closed(commands, "run-2");
        verify(!AccountRequests.isLoading(commands, "codex"));
        verify(AccountRequests.isLoading(commands, "claude"));
    }

    function test_timeoutReleasesLoadingAndItsLateReplyIsIgnored() {
        var commands = start(({}), "run-1", "codex", "accounts-context-a");
        commands = start(commands, "run-2", "claude", "claude-context");
        compare(CommandLedger.expired(commands, 60999).length, 0);
        var expired = CommandLedger.expired(commands, 61000);
        compare(expired.length, 2);
        commands = CommandLedger.closed(commands, "run-1");
        verify(!AccountRequests.isLoading(commands, "codex"));
        verify(AccountRequests.isLoading(commands, "claude"));
        commands = start(commands, "run-3", "codex", "accounts-context-a");
        compare(AccountRequests.completion(commands, "run-1", "accounts-context-a"), null);
        verify(AccountRequests.isLoading(commands, "codex"));
    }

    function test_usageRefreshDoesNotOwnAccountLoading() {
        var commands = start(({}), "accounts", "codex", "accounts-context-a");
        commands = CommandLedger.opened(commands, "usage", CommandLedger.descriptor("usage", "codex", 1000, 120000, 120000));
        compare(AccountRequests.completion(commands, "usage", "accounts-context-a"), null);
        commands = CommandLedger.closed(commands, "usage");
        verify(AccountRequests.isLoading(commands, "codex"));
        verify(AccountRequests.completion(commands, "accounts", "accounts-context-a").acceptsPayload);
        commands = CommandLedger.closed(commands, "accounts");
        verify(!AccountRequests.isLoading(commands, "codex"));
    }

    function test_unknownAndInheritedSourcesHaveNoCompletion() {
        var inherited = start(({}), "inherited", "codex", "accounts-context-a");
        var commands = Object.create(inherited);
        verify(!AccountRequests.isLoading(commands, "codex"));
        compare(AccountRequests.completion(commands, "inherited", "accounts-context-a"), null);
        compare(AccountRequests.completion(commands, "unknown", "accounts-context-a"), null);
        compare(AccountRequests.completion(commands, "toString", "accounts-context-a"), null);
    }

    function test_decisionsDoNotMutateTheLedger() {
        var commands = start(({}), "run-1", "codex", "accounts-context-a");
        var before = JSON.stringify(commands);
        AccountRequests.completion(commands, "run-1", "accounts-context-a");
        AccountRequests.completion(commands, "run-1", "accounts-context-b");
        AccountRequests.isLoading(commands, "codex");
        compare(JSON.stringify(commands), before);
    }
}
