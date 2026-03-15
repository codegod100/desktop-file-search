import QtQuick
import QtQuick.Controls

Button {
    id: control

    required property var theme
    property color surfaceColor: theme.surfaceLeft
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
            font.pixelSize: 15
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            renderType: Text.QtRendering
        }
    }

    background: Rectangle {
        readonly property color baseSurfaceColor: control.backgroundColor.a > 0 ? control.backgroundColor : control.surfaceColor
        radius: 0
        color: control.enabled
            ? (
                control.down
                    ? (control.pressedColor.a > 0 ? control.pressedColor : Qt.darker(baseSurfaceColor, 1.08))
                    : control.hovered
                        ? (control.hoverColor.a > 0 ? control.hoverColor : Qt.lighter(baseSurfaceColor, 1.08))
                        : baseSurfaceColor
            )
            : Qt.darker(baseSurfaceColor, 1.08)
        border.width: 1
        border.color: control.enabled
            ? (control.borderColor.a > 0 ? control.borderColor : control.theme.borderStrong)
            : Qt.darker(control.theme.borderStrong, 1.08)
    }
}
