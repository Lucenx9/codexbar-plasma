import QtQuick
import "../Guards.js" as Guards

Item {
    id: controller

    property var configuration: null
    property bool consented: false
    property string endpoint: ""
    property string widgetVersion: ""

    readonly property bool available: endpoint.length <= 512
        && /^https:\/\/[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+\/v1\/telemetry$/.test(endpoint)
        && /^(?:0|[1-9][0-9]{0,2})(?:\.(?:0|[1-9][0-9]{0,2})){2}$/.test(widgetVersion)
    readonly property bool sending: sender.busy

    function startAttempt(attempt) {
        pending.attempt = pending.mayReport() && Guards.isNonNegativeInteger(attempt) ? attempt : -1;
    }

    function finishAttempt(attempt, outcome) {
        if (pending.attempt === -1 || pending.attempt !== attempt)
            return;

        pending.attempt = -1;
        if (!pending.mayReport() || pending.outcomes.indexOf(outcome) === -1)
            return;

        // Claim this release before sending. A transport failure has no retry.
        const version = widgetVersion;
        const destination = endpoint;
        const settings = configuration;
        settings.telemetrySubmittedVersion = version;
        if (!consented || endpoint !== destination || widgetVersion !== version || configuration !== settings)
            return;

        const json = JSON.stringify({schema: 1, widget_version: version, outcome: outcome});
        const command = "curl --disable --proto =https --no-location --max-time 5 --silent --output /dev/null"
            + " --header 'Content-Type: application/json' --data-raw " + Guards.shellQuote(json)
            + " -- " + Guards.shellQuote(destination);
        sender.start(command, null, 5000);
    }

    onConfigurationChanged: pending.retire()
    onConsentedChanged: pending.retire()
    onEndpointChanged: pending.retire()
    onWidgetVersionChanged: pending.retire()

    QtObject {
        id: pending

        property int attempt: -1
        readonly property var outcomes: ["success", "cli_unavailable", "invalid_response", "timeout", "other_error"]

        function mayReport() {
            return controller.available && controller.consented && controller.configuration !== null
                && controller.configuration.telemetrySubmittedVersion !== controller.widgetVersion;
        }

        function retire() {
            attempt = -1;
            sender.cancel();
        }
    }

    CliProcess {
        id: sender
    }
}
