import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

Item {
    id: probe

    required property var applet
    required property var usageLifecycle
    required property string scenario
    required property string imagePath
    property bool cacheRestart: false
    property int step: 0
    property var refreshedProvider
    property real savedScroll: 0

    Rectangle {
        parent: probe.applet.fullRepresentationItem
        anchors.fill: parent
        z: -1
        color: Kirigami.Theme.backgroundColor
    }

    function verify(condition, message) {
        if (!condition)
            throw new Error("SMOKE_FAILED: " + message);
    }

    function find(item, name) {
        if (item.objectName === name)
            return item;
        for (var child of item.children) {
            var result = find(child, name);
            if (result)
                return result;
        }
        return null;
    }

    function longProvider(provider, account) {
        var rows = [];
        for (var index = 0; index < 48; index++)
            rows.push({
                label: "Synthetic detail " + index,
                value: "Measured " + index
            });
        return applet.normalizeProvider({
            provider: provider,
            account: account,
            usage: {
                updatedAt: new Date().toISOString(),
                primary: {
                    usedPercent: 43
                },
                details: [
                    {
                        title: "Synthetic details",
                        rows: rows
                    }
                ]
            }
        });
    }

    function verifyViewport(popup, scroll) {
        verify(scroll.height > 0, "the popup scroll viewport collapsed");
        verify(scroll.mapToItem(popup, 0, scroll.height).y <= popup.height + 1, "the popup scroll viewport left the popup bounds");
    }

    function accountButtons(item) {
        var buttons = item.fullLabel !== undefined ? [item] : [];
        for (var child of item.children)
            buttons = buttons.concat(accountButtons(child));
        return buttons;
    }

    function buttonWithText(item, text) {
        if (item.text === text && typeof item.clicked === "function" && item.visible)
            return item;
        for (var child of item.children) {
            var found = buttonWithText(child, text);
            if (found)
                return found;
        }
        return null;
    }

    function revealAndVerify(scroll, item) {
        verify(item !== null, "the scroll target is missing");
        var bottom = item.mapToItem(scroll.contentItem.contentItem, 0, item.height).y;
        scroll.contentItem.cancelFlick();
        scroll.contentItem.contentY = Math.max(0, Math.min(scroll.contentItem.contentHeight - scroll.contentItem.height, bottom - scroll.contentItem.height));
        var top = item.mapToItem(scroll.contentItem, 0, 0).y;
        verify(top >= -1 && top + item.height <= scroll.contentItem.height + 1, "the complete final control cannot be reached by scrolling");
    }

    function verifyGlobalBanner(popup, scroll) {
        var banner = find(popup, "globalErrorMessage");
        verify(banner.visible && banner.actions.length === 2, "the global error lost its recovery actions");
        verify(Math.abs(banner.mapToItem(scroll.contentItem, 0, 0).y) < 1, "the global error did not precede the scrollable content");
        verifyViewport(popup, scroll);
        revealAndVerify(scroll, buttonWithText(banner, banner.actions[1].text));
        scroll.contentItem.contentY = 0;
    }

    Component.onCompleted: applet.expanded = true

    Timer {
        interval: 200
        running: true
        repeat: true

        onTriggered: {
            var popup = applet.fullRepresentationItem;
            if (!popup || popup.width <= 0 || popup.height <= 0 || applet.loading)
                return;
            var scroll = probe.find(popup, "providerScroll");
            if (probe.step === 0) {
                if (applet.providers.length !== 2)
                    return;
                usageLifecycle.initialized = false;
                usageLifecycle.retireUsageCommands();
                applet.usageLifecycleInitialized = false;
                applet.Plasmoid.configuration.autoSelectProvider = false;
                applet.commitUsageSnapshot([probe.longProvider("codex", "first@example.com"), probe.longProvider("claude", "first@example.com")]);
                applet.openProviderFromPanel("codex");
                applet.loadAccounts("codex");
            } else if (probe.step === 1) {
                if (applet.accountLoadingForProvider("codex") || applet.accountOptionsForProvider("codex").length !== 20)
                    return;
                probe.verifyViewport(popup, scroll);
                probe.verify(scroll.contentItem.contentHeight > scroll.height, "the long account list cannot be scrolled");
                var buttons = probe.accountButtons(popup);
                probe.verify(buttons.length === 20, "not every discovered account received a button");
                probe.revealAndVerify(scroll, buttons[buttons.length - 1]);
                scroll.contentItem.contentY = 400;
                probe.savedScroll = scroll.contentItem.contentY;
                probe.verify(probe.savedScroll >= 399, "the accounts did not create scrollable content");
                probe.refreshedProvider = applet.selectedProviderData;
                applet.replaceProviderSnapshot("codex", Object.assign({}, probe.refreshedProvider));
            } else if (probe.step === 2) {
                probe.verify(Math.abs(scroll.contentItem.contentY - probe.savedScroll) < 1, "a refresh of the same account reset scrolling");
                applet.openProviderFromPanel("codex");
                probe.verify(Math.abs(scroll.contentItem.contentY - probe.savedScroll) < 1, "selecting the same provider reset scrolling");
                scroll.contentItem.contentY = 50;
                applet.Plasmoid.configuration.privacyMode = true;
            } else if (probe.step === 3) {
                probe.verify(Math.abs(scroll.contentItem.contentY - 50) < 1, "privacy presentation changed account scroll identity");
                applet.Plasmoid.configuration.privacyMode = false;
                applet.openProviderFromPanel("claude");
            } else if (probe.step === 4) {
                probe.verify(Math.abs(scroll.contentItem.contentY) < 1, "provider selection retained the preceding provider's scroll");
                scroll.contentItem.contentY = 400;
                applet.replaceProviderSnapshot("claude", probe.longProvider("claude", "second@example.com"));
            } else if (probe.step === 5) {
                probe.verify(Math.abs(scroll.contentItem.contentY) < 1, "account identity changes retained the preceding account's scroll");
                scroll.contentItem.contentY = 400;
                applet.selectAccount("claude", "second@example.com");
            } else if (probe.step === 6) {
                probe.verify(Math.abs(scroll.contentItem.contentY) < 1, "an explicit account override retained the previous scroll");
                scroll.contentItem.contentY = 400;
                applet.selectAccount("claude", "");
            } else if (probe.step === 7) {
                probe.verify(Math.abs(scroll.contentItem.contentY) < 1, "clearing an account override retained the previous scroll");
                applet.selectGlobalView("overview");
            } else if (probe.step === 8) {
                applet.openProviderFromPanel("claude");
            } else if (probe.step === 9) {
                probe.verify(Math.abs(scroll.contentItem.contentY) < 1, "returning from a global view retained an unrelated scroll");
                var provider = Object.assign({}, applet.selectedProviderData, {
                    error: new Array(17).join("Synthetic bounded error detail. ")
                });
                applet.replaceProviderSnapshot("claude", provider);
            } else if (probe.step === 10) {
                probe.verifyViewport(popup, scroll);
                var banner = probe.find(popup, "providerErrorMessage");
                probe.verify(banner.visible && banner.actions.length === 2, "the provider error lost recovery actions");
                probe.revealAndVerify(scroll, probe.buttonWithText(banner, banner.actions[1].text));
                scroll.contentItem.contentY = 0;
                applet.replaceProviderSnapshot("claude", probe.longProvider("claude", "second@example.com"));
                usageLifecycle.errorText = new Array(17).join("Synthetic bounded global error. ");
            } else if (probe.step === 11) {
                probe.verifyGlobalBanner(popup, scroll);
                applet.selectGlobalView("overview");
            } else if (probe.step === 12) {
                var overview = probe.find(popup, "overviewScroll");
                probe.verifyGlobalBanner(popup, overview);
                applet.selectGlobalView("spend");
            } else if (probe.step === 13) {
                probe.verify(!probe.find(popup, "globalErrorMessage").visible, "provider errors leaked into the independent Spend view");
                applet.selectGlobalView("overview");
            } else if (probe.step === 14) {
                probe.verifyGlobalBanner(popup, probe.find(popup, "overviewScroll"));
                applet.providers = [];
                applet.selectedProviderID = "";
            } else if (probe.step === 15) {
                probe.verifyGlobalBanner(popup, probe.find(popup, "emptyErrorScroll"));
                usageLifecycle.errorText = "";
            } else if (probe.step === 16) {
                probe.verify(!probe.find(popup, "globalErrorMessage").visible, "a cleared error remained visible");
                usageLifecycle.errorText = new Array(17).join("Synthetic bounded global error. ");
            } else {
                probe.verifyGlobalBanner(popup, probe.find(popup, "emptyErrorScroll"));
                console.log("SMOKE_CAPTURE_START:" + probe.scenario);
                var accepted = popup.grabToImage(function (result) {
                    probe.verify(result.saveToFile(probe.imagePath), "could not save popup screenshot");
                    console.log("SMOKE_CAPTURED:" + probe.scenario);
                });
                probe.verify(accepted, "could not capture popup");
                stop();
            }
            probe.step++;
        }
    }
}
