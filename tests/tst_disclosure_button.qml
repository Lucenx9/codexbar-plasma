import QtQuick
import QtTest
import "../contents/ui/components" as Components

TestCase {
    name: "DisclosureButton"
    when: windowShown
    width: 400
    height: 200

    Component {
        id: disclosureComponent

        Item {
            property bool open: false
            readonly property alias button: disclosure

            Components.DisclosureButton {
                id: disclosure
                plainText: "More options"
                expanded: parent.open
                onClicked: parent.open = !parent.open
            }
        }
    }

    Component {
        id: mirroredComponent

        Item {
            readonly property alias button: disclosure

            LayoutMirroring.enabled: true
            LayoutMirroring.childrenInherit: true

            Components.DisclosureButton {
                id: disclosure
                plainText: "More options"
            }
        }
    }

    // The owner keeps the state; the button reports it without a checked
    // background, and the keyboard toggles it like a pointer click.
    function test_ownerStateDrivesArrowAndAccessibleState() {
        var host = createTemporaryObject(disclosureComponent, this);
        var button = host.button;
        verify(button.flat);
        verify(!button.checkable);
        compare(button.Accessible.name, "More options");
        verify(button.Accessible.checkable);
        verify(!button.Accessible.checked);
        compare(button.icon.name, "arrow-right");

        button.forceActiveFocus();
        keyClick(Qt.Key_Space);
        verify(host.open && button.expanded);
        verify(button.Accessible.checked);
        compare(button.icon.name, "arrow-down");
        verify(!button.checked);

        keyClick(Qt.Key_Space);
        verify(!host.open && !button.expanded && !button.Accessible.checked);
        verify(button.activeFocus);
    }

    function test_collapsedArrowFollowsLayoutDirection() {
        var host = createTemporaryObject(mirroredComponent, this);
        compare(host.button.icon.name, "arrow-left");
        host.button.expanded = true;
        compare(host.button.icon.name, "arrow-down");
    }
}
