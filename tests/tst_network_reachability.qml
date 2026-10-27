import QtQuick
import QtTest

TestCase {
    name: "NetworkReachability"

    Loader {
        id: reachabilityLoader
        source: Qt.resolvedUrl("../contents/ui/controllers/NetworkReachability.qml")
    }

    // The production adapter loads on the supported Qt stack and exposes a
    // QNetworkInformation::Reachability value (0 unknown through 4 online).
    function test_adapterLoadsAndReportsAReachabilityValue() {
        compare(reachabilityLoader.status, Loader.Ready)
        var value = reachabilityLoader.item.reachability
        compare(typeof value, "number")
        verify(value >= 0 && value <= 4, String(value))
    }
}
