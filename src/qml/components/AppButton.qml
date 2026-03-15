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
    readonly property color fallbackButtonBg: "#596071"
    readonly property color fallbackButtonHover: "#646c7f"
    readonly property color fallbackButtonPressed: "#4d5565"
    readonly property color fallbackButtonBorder: "#2a2f38"
    readonly property color fallbackButtonText: "#eff0f1"

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
                ? (control.textColor.a > 0
                    ? control.textColor
                    : (control.theme && control.theme.buttonText !== undefined ? control.theme.buttonText : control.fallbackButtonText))
                : "#7d8794"
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
                    ? (control.pressedColor.a > 0
                        ? control.pressedColor
                        : (control.theme && control.theme.buttonPressed !== undefined ? control.theme.buttonPressed : control.fallbackButtonPressed))
                    : control.hovered
                        ? (control.hoverColor.a > 0
                            ? control.hoverColor
                            : (control.theme && control.theme.buttonHover !== undefined ? control.theme.buttonHover : control.fallbackButtonHover))
                        : (control.backgroundColor.a > 0
                            ? control.backgroundColor
                            : (control.theme && control.theme.buttonBg !== undefined ? control.theme.buttonBg : control.fallbackButtonBg))
            )
            : "#525866"
        border.width: 1
        border.color: control.enabled
            ? (control.borderColor.a > 0
                ? control.borderColor
                : (control.theme && control.theme.buttonBorder !== undefined ? control.theme.buttonBorder : control.fallbackButtonBorder))
            : "#454c5a"
    }
}
