import QtQuick
import QtQuick.Controls

Button {
    id: control

    required property var theme
    property color backgroundColor: "transparent"
    property color hoverColor: "transparent"
    property color pressedColor: "transparent"
    property color borderColor: "transparent"
    property color textColor: "transparent"

    implicitHeight: 34
    implicitWidth: Math.max(120, contentItem.implicitWidth + leftPadding + rightPadding)
    leftPadding: 18
    rightPadding: 18
    topPadding: 7
    bottomPadding: 7

    contentItem: Item {
        implicitWidth: buttonLabel.implicitWidth
        implicitHeight: buttonLabel.implicitHeight

        Text {
            id: buttonLabel
            anchors.centerIn: parent
            text: control.text
            color: control.enabled
                ? (control.textColor.a > 0 ? control.textColor : control.theme.textPrimary)
                : Qt.darker(control.theme.textSecondary, 1.5)
            font.pixelSize: 13
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            renderType: Text.QtRendering
        }
    }

    background: Rectangle {
        radius: 2
        color: control.enabled
            ? (
                control.down
                    ? (control.pressedColor.a > 0 ? control.pressedColor : Qt.darker(Qt.lighter(control.theme.surfaceRaised, 1.28), 1.12))
                    : control.hovered
                        ? (control.hoverColor.a > 0 ? control.hoverColor : Qt.lighter(Qt.lighter(control.theme.surfaceRaised, 1.28), 1.08))
                        : (control.backgroundColor.a > 0 ? control.backgroundColor : Qt.lighter(control.theme.surfaceRaised, 1.28))
            )
            : Qt.darker(Qt.lighter(control.theme.surfaceRaised, 1.28), 1.08)
        border.width: 1
        border.color: control.enabled
            ? (control.borderColor.a > 0 ? control.borderColor : control.theme.borderSoft)
            : Qt.darker(control.theme.borderSoft, 1.08)
    }
}
