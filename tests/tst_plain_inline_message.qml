import QtQuick
import QtTest
import "../contents/ui/components" as Components

TestCase {
    name: "PlainTextComponents"

    readonly property string adversarialText: "Status <img src=\"http://127.0.0.1/probe\"> & <test-org>"
    readonly property string escapedText: "<span>Status &lt;img src=&quot;http://127.0.0.1/probe&quot;&gt; &amp; &lt;test-org&gt;</span>"

    Component {
        id: messageComponent

        Components.PlainInlineMessage {
            plainText: adversarialText
        }
    }

    Component {
        id: controlsLabelComponent

        Components.PlainControlsLabel {
            text: adversarialText
        }
    }

    Component {
        id: plasmaLabelComponent

        Components.PlainPlasmaLabel {
            text: adversarialText
        }
    }

    Component {
        id: headingComponent

        Components.PlainHeading {
            text: adversarialText
        }
    }

    Component {
        id: placeholderComponent

        Components.PlainPlaceholderMessage {
            plainText: adversarialText
            plainExplanation: adversarialText
        }
    }

    function test_componentFeedsOnlyEscapedMarkupToKirigami() {
        var message = createTemporaryObject(messageComponent, this)
        verify(message !== null)
        compare(message.plainText, adversarialText)
        compare(message.text, escapedText)
        compare(message.Accessible.name, adversarialText)
    }

    function test_labelsForcePlainText() {
        var controlsLabel = createTemporaryObject(controlsLabelComponent, this)
        var plasmaLabel = createTemporaryObject(plasmaLabelComponent, this)
        var heading = createTemporaryObject(headingComponent, this)
        verify(controlsLabel !== null)
        verify(plasmaLabel !== null)
        verify(heading !== null)
        compare(controlsLabel.textFormat, Text.PlainText)
        compare(plasmaLabel.textFormat, Text.PlainText)
        compare(heading.textFormat, Text.PlainText)
        compare(controlsLabel.text, adversarialText)
        compare(plasmaLabel.text, adversarialText)
        compare(heading.text, adversarialText)
    }

    function test_placeholderEscapesTitleAndExplanation() {
        var placeholder = createTemporaryObject(placeholderComponent, this)
        verify(placeholder !== null)
        compare(placeholder.text, escapedText)
        compare(placeholder.explanation, escapedText)
        compare(placeholder.Accessible.name, adversarialText)
    }
}
