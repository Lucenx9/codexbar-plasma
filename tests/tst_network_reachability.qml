import QtQuick
import QtTest

TestCase {
    name: "NetworkReachability"

    readonly property url adapterUrl: Qt.resolvedUrl("../contents/ui/controllers/NetworkReachability.qml")

    // The production adapter exposes a QNetworkInformation::Reachability value
    // (0 unknown through 4 online). QtNetwork's NetworkInformation is optional
    // (Qt 6.7+); CI provides it and rejects skips.
    function test_adapterLoadsAndReportsAReachabilityValue() {
        var component = Qt.createComponent(adapterUrl)
        if (component.status === Component.Error && /QtNetwork|NetworkInformation/.test(component.errorString()))
            skip("NetworkInformation needs the optional QtNetwork QML module from Qt 6.7")
        compare(component.status, Component.Ready, component.errorString())
        var adapter = createTemporaryObject(component, this)
        verify(adapter !== null)
        compare(typeof adapter.reachability, "number")
        verify(adapter.reachability >= 0 && adapter.reachability <= 4, String(adapter.reachability))
    }
}
