import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Window
import QtTest

// Opening the Popup and Notifications settings pages must not shift text or
// controls: the ScrollView briefly reserves a scrollbar gutter after the
// first paint and then releases it, reflowing every wrapped paragraph by
// that gutter width. Sampling rendered frames while the real pages settle
// (including the provider roster arriving after opening) keeps that
// viewport width pinned.
TestCase {
    id: testCase
    name: "PopupNotificationsGeometry"
    when: windowShown
    visible: true
    width: 600
    height: 500

    property bool mirroredPage: false
    property var observedPage: null
    property double observedGutter: 0
    property var measuredItems: []
    property var positions: []
    property var paddings: []
    property var contentHeights: []

    LayoutMirroring.enabled: mirroredPage
    LayoutMirroring.childrenInherit: true

    function i18n(text, value, second) {
        var result = value === undefined ? text : text.replace("%1", value);
        return second === undefined ? result : result.replace("%2", second);
    }

    function i18np(singular, plural, count) {
        return (count === 1 ? singular : plural).replace("%1", count);
    }

    // A settled scene may otherwise render only once on the software backend.
    Timer {
        interval: 50
        repeat: true
        running: testCase.measuredItems.length > 0
        onTriggered: testCase.Window.window.update()
    }

    Connections {
        target: testCase.Window.window

        function onFrameSwapped() {
            if (testCase.measuredItems.length > 0 && testCase.observedPage !== null) {
                testCase.positions.push(testCase.measuredItems.map(function (item) {
                    return item.mapToItem(testCase, 0, 0);
                }));
                var view = testCase.observedPage.contentItem;
                testCase.paddings.push([view.leftPadding, view.rightPadding]);
                testCase.contentHeights.push(testCase.observedPage.flickable.contentHeight);
            }
        }
    }

    function createPage(source, properties) {
        var component = Qt.createComponent(source);
        if (component.status === Component.Error && /module "org\.kde\.[^"]+" is not installed/.test(component.errorString())) {
            skip("Settings geometry checks need the optional KDE QML modules");
            return null;
        }
        compare(component.status, Component.Ready, component.errorString());
        failOnWarning(/.*/);
        var page = createTemporaryObject(component, testCase, Object.assign({
            width: testCase.width,
            height: testCase.height
        }, properties || {}));
        verify(page !== null);
        observedPage = page;
        // Read through the function-local page: qmllint cannot use a var
        // property for prefixed attached-property access.
        observedGutter = page.contentItem.Controls.ScrollBar.vertical.implicitWidth;
        return page;
    }

    function cleanup() {
        measuredItems = [];
        positions = [];
        paddings = [];
        contentHeights = [];
        observedPage = null;
        observedGutter = 0;
        mirroredPage = false;
    }

    function expectedGutter() {
        return observedGutter;
    }

    // The creation-time roster load is asynchronous: commandRunSerial proves it
    // ran, and an empty ledger with loading settled proves its reply was
    // processed (and its process exited), so later manual roster states and
    // page destruction cannot race a late CLI reply. The load lives in the
    // shared roster controller, so drive it there, not through the page.
    function rosterController(page) {
        var controller = findChild(page, "providerRosterController");
        verify(controller !== null, "providerRosterController");
        return controller;
    }

    function waitForRosterSettled(page) {
        var controller = rosterController(page);
        tryVerify(function () {
            return controller.commandRunSerial > 0 && !controller.providerRosterLoading && !controller.hasPendingProviderRosterCommands();
        });
    }

    // Every rendered frame must keep the same viewport width (the gutter stays
    // reserved) and the same control positions. Notifications content is
    // static, so its height must settle too; the popup roster arrives below
    // the measured controls, so that page checks geometry only.
    function verifyViewportStill(names, checkHeight) {
        verify(positions.length >= 3, "Fewer than three rendered frames were observed");
        var gutter = expectedGutter();
        var padIndex = mirroredPage ? 0 : 1;
        for (var frame = 0; frame < positions.length; frame++) {
            var pads = paddings[frame];
            verify(Math.abs(pads[padIndex] - gutter) < 0.5, "viewport padding changed from " + gutter + " to " + pads[padIndex] + " in frame " + frame);
            for (var item = 0; item < names.length; item++) {
                var start = positions[0][item];
                var current = positions[frame][item];
                verify(Math.abs(current.x - start.x) < 0.5 && Math.abs(current.y - start.y) < 0.5, names[item] + " shifted from " + start + " to " + current + " in frame " + frame);
            }
            if (checkHeight) {
                verify(Math.abs(contentHeights[frame] - contentHeights[0]) < 0.5, "content height changed from " + contentHeights[0] + " to " + contentHeights[frame] + " in frame " + frame);
            }
        }
    }

    function test_notificationsOpeningKeepsViewportStill_data() {
        return [
            {
                tag: "compact",
                pageWidth: 600,
                pageHeight: 500,
                fontSize: 13,
                rtl: false
            },
            {
                tag: "narrow",
                pageWidth: 420,
                pageHeight: 640,
                fontSize: 13,
                rtl: false
            },
            {
                tag: "large-font",
                pageWidth: 600,
                pageHeight: 500,
                fontSize: 20,
                rtl: false
            },
            {
                tag: "rtl",
                pageWidth: 600,
                pageHeight: 500,
                fontSize: 13,
                rtl: true
            }
        ];
    }

    function test_notificationsOpeningKeepsViewportStill(data) {
        width = data.pageWidth;
        height = data.pageHeight;
        mirroredPage = data.rtl;
        var page = createPage("../contents/ui/configNotifications.qml", {
            "font.pixelSize": data.fontSize,
            cfg_quotaWarningPercent: 80,
            cfg_quotaCriticalPercent: 95
        });
        if (!page)
            return;
        var names = ["quotaWarningPercentSpin", "quotaCriticalPercentSpin", "notifyStatusIncidentsCheck"];
        measuredItems = names.map(function (name) {
            var item = findChild(page, name);
            verify(item !== null, name);
            return item;
        });
        wait(1000);
        measuredItems = [];
        verifyViewportStill(names, true);
    }

    function test_popupOpeningKeepsViewportStill_data() {
        return [
            {
                tag: "ltr",
                rtl: false
            },
            {
                tag: "rtl",
                rtl: true
            }
        ];
    }

    function test_popupOpeningKeepsViewportStill(data) {
        width = 600;
        height = 700;
        mirroredPage = data.rtl;
        // "true" exits immediately with empty stdout, so the creation-time
        // roster load settles fast without touching the network. The roster
        // states below then mirror the provider list arriving after opening.
        var page = createPage("../contents/ui/configPopup.qml", {
            cfg_commandPath: "true",
            cfg_providerOrder: "",
            cfg_overviewProviderIDs: ""
        });
        if (!page)
            return;
        // Let the creation-time roster load settle before driving states, so
        // no late CLI reply can rewrite the roster mid-observation.
        waitForRosterSettled(page);
        var controller = rosterController(page);
        controller.providerRosterError = "";
        controller.providerRosterLoading = true;
        var names = ["showPopupPaceCheck", "showPopupCreditsCheck", "showPopupProviderDetailsCheck"];
        measuredItems = names.map(function (name) {
            var item = findChild(page, name);
            verify(item !== null, name);
            return item;
        });
        wait(500);
        controller.enabledProviderRoster = [
            {
                provider: "codex",
                displayName: "Codex"
            },
            {
                provider: "claude",
                displayName: "Claude"
            },
            {
                provider: "gemini",
                displayName: "Gemini"
            }
        ];
        controller.providerRosterLoading = false;
        wait(700);
        measuredItems = [];
        verifyViewportStill(names, false);
    }

    function test_mirrorChangeRestoresOppositePadding_data() {
        return [
            {
                tag: "notifications",
                source: "../contents/ui/configNotifications.qml",
                properties: {
                    cfg_quotaWarningPercent: 80,
                    cfg_quotaCriticalPercent: 95
                }
            },
            {
                tag: "popup",
                source: "../contents/ui/configPopup.qml",
                properties: {
                    cfg_commandPath: "true",
                    cfg_providerOrder: "",
                    cfg_overviewProviderIDs: ""
                }
            }
        ];
    }

    function test_mirrorChangeRestoresOppositePadding(data) {
        width = 600;
        height = 500;
        var page = createPage(data.source, data.properties);
        if (!page)
            return;
        if (data.tag === "popup") {
            // Destroying the page while its creation-time CLI request is
            // still running warns; the "true" command settles immediately.
            waitForRosterSettled(page);
        }
        var view = page.contentItem;
        var gutter = expectedGutter();
        tryCompare(view, "rightPadding", gutter);
        compare(view.leftPadding, 0);
        mirroredPage = true;
        tryCompare(page, "mirrored", true);
        tryCompare(view, "leftPadding", gutter);
        tryCompare(view, "rightPadding", 0);
        mirroredPage = false;
        tryCompare(view, "leftPadding", 0);
        tryCompare(view, "rightPadding", gutter);
    }
}
