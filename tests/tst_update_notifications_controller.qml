import QtQuick
import QtTest
import "../contents/ui/controllers" as Controllers

TestCase {
    id: testCase
    name: "UpdateNotificationsController"
    property var subject: null
    property var config: null
    property var sent: []
    property var opened: []
    property string nextSource: ""
    property var memoAtSend: []

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++) text = text.replace("%" + i, arguments[i])
        return text
    }
    Component {
        id: configurationComponent
        QtObject {
            property bool updateNotificationsEnabled: true
            property bool cliUpdateNotificationsEnabled: true
            property string lastNotifiedUpdateVersion: ""
            property string cliUpdateLastNotifiedVersion: ""
        }
    }
    Component {
        id: controllerComponent
        Controllers.UpdateNotificationsController {
            onReleasePageRequested: function(url) {
                testCase.opened = testCase.opened.concat([url])
                // Activation must retire its source before any external effect.
                compare(Object.keys(pendingUpdateReleaseUrls).length, 0)
            }
        }
    }
    function init() {
        sent = []; opened = []; memoAtSend = []; nextSource = "source-1"
        config = createTemporaryObject(configurationComponent, this)
        subject = createTemporaryObject(controllerComponent, this, {
            configuration: config,
            dispatcher: {send: function(title, body, urgency, actionLabel) {
                sent = sent.concat([{title: title, body: body, urgency: urgency, actionLabel: actionLabel}])
                memoAtSend = memoAtSend.concat([{
                    widget: config.lastNotifiedUpdateVersion, cli: config.cliUpdateLastNotifiedVersion
                }])
                return nextSource
            }}
        })
        verify(subject !== null)
    }
    function test_widgetCommitsBeforeSendCliCommitsAfterSend() {
        subject.notifyAvailableUpdate(" v1 ", "asset", "https://github.com/widget/v1")
        compare(memoAtSend[0].widget, "v1")
        compare(config.lastNotifiedUpdateVersion, "v1")
        subject.notifyAvailableCliUpdate("v1", "https://github.com/cli/v1")
        compare(memoAtSend[1].cli, "")
        compare(config.cliUpdateLastNotifiedVersion, "v1")
        subject.notifyAvailableUpdate("v1", "asset", "https://github.com/widget/v1")
        subject.notifyAvailableCliUpdate("v1", "https://github.com/cli/v1")
        compare(sent.length, 2)
    }
    function test_dispatchFailureAndUnsafeSource_data() {
        return [{tag: "not-started", source: ""}, {tag: "unsafe", source: "__proto__"}]
    }
    function test_dispatchFailureAndUnsafeSource(data) {
        nextSource = data.source
        subject.notifyAvailableUpdate("v1", "", "https://github.com/widget/v1")
        subject.notifyAvailableCliUpdate("v2", "https://github.com/cli/v2")
        compare(config.lastNotifiedUpdateVersion, "v1")
        compare(config.cliUpdateLastNotifiedVersion, "")
        compare(subject.pendingUpdateReleaseUrls, ({}))
        subject.notifyAvailableCliUpdate("v2", "https://github.com/cli/v2")
        compare(sent.length, 3)
    }
    function test_switchesStayIndependentAndReactive() {
        config.updateNotificationsEnabled = false
        subject.notifyAvailableUpdate("v1", "", "")
        subject.notifyInstalledUpdate("v1")
        subject.notifyAvailableCliUpdate("v1", "")
        compare(sent.length, 1)
        config.cliUpdateNotificationsEnabled = false
        config.updateNotificationsEnabled = true
        subject.notifyAvailableUpdate("v2", "", "")
        subject.notifyAvailableCliUpdate("v2", "")
        compare(sent.length, 2)
        subject.enableNotifications = false
        subject.notifyAvailableUpdate("v3", "", "")
        subject.notifyInstalledUpdate("v3")
        subject.notifyAvailableCliUpdate("v3", "")
        compare(sent.length, 2)
        compare(config.lastNotifiedUpdateVersion, "v2")
        compare(config.cliUpdateLastNotifiedVersion, "v1")
    }
    function test_privacyAppliesToEveryNotificationKind() {
        subject.privacyMode = true
        subject.notifyAvailableUpdate("v1", "", "https://github.com/widget/v1")
        subject.notifyInstalledUpdate("v1")
        subject.notifyAvailableCliUpdate("v2", "https://github.com/cli/v2")
        subject.send("Private provider", "Private status", "critical", "")
        compare(sent.length, 4)
        for (var message of sent) {
            compare(message.title, "CodexBar")
            compare(message.body, "Usage or status changed. Open CodexBar for details.")
        }
        compare(sent[0].actionLabel, "Open release page")
        compare(sent[3].urgency, "critical")
        subject.privacyMode = false
        subject.send(" provider ", " status ", "low", "")
        compare(sent[4].title, "provider")
        compare(sent[4].body, "status")
    }
    function test_sourcesRetireBeforeOpeningAndReplayIsIgnored() {
        subject.notifyAvailableCliUpdate("v1", "https://github.com/cli/v1")
        subject.handleUpdateNotificationActivated("unrelated")
        compare(opened, [])
        subject.enableNotifications = false
        subject.privacyMode = true
        subject.handleUpdateNotificationActivated("source-1")
        compare(opened, ["https://github.com/cli/v1"])
        subject.handleUpdateNotificationActivated("source-1")
        compare(opened.length, 1)
    }
    function test_installedAndVersionlessWidgetMessages() {
        subject.notifyInstalledUpdate(" v1 ")
        compare(sent[0].title, "CodexBar widget update installed")
        compare(sent[0].body, "Version v1 was installed. Restart Plasma to apply the new widget version.")
        subject.notifyAvailableUpdate("", "asset-url", "")
        compare(sent[1].body, "A new widget version is available.")
        compare(sent[1].actionLabel, "")
        subject.notifyAvailableUpdate("", "asset-url", "")
        compare(sent.length, 2)
    }
    function test_persistedWidgetVersionSurvivesRecreation() {
        config.lastNotifiedUpdateVersion = "v1"
        var restarted = createTemporaryObject(controllerComponent, this, {
            configuration: config, dispatcher: subject.dispatcher
        })
        restarted.notifyAvailableUpdate("v1", "", "")
        compare(sent.length, 0)
    }
}
