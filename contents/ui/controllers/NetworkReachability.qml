import QtQml
import QtNetwork

// Loaded only through a Loader: QtNetwork exposes NetworkInformation from
// Qt 6.7, while Plasma 6.0 may run on Qt 6.6. A failed load, or a missing
// backend, leaves the applet with unknown reachability.
QtObject {
    readonly property int reachability: NetworkInformation.reachability
}
