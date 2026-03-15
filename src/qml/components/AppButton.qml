import QtQuick
import QtQuick.Controls

Button {
    id: control

    required property var theme
    readonly property color fallbackButtonBg: "#444a58"
    readonly property color fallbackButtonHover: "#4c5362"
    readonly property color fallbackButtonPressed: "#3b414d"
    readonly property color fallbackButtonBorder: "#5b6272"
    readonly property color fallbackButtonText: "#eff0f1"

    implicitHeight: 46
    implicitWidth: Math.max(120, contentItem.implicitWidth + leftPadding + rightPadding)
    leftPadding: 18
    rightPadding: 18
    topPadding: 11
    bottomPadding: 11

    contentItem: Text {
        text: control.text
        color: control.enabled
            ? (control.theme && control.theme.buttonText !== undefined ? control.theme.buttonText : control.fallbackButtonText)
            : "#7d8794"
        font.pixelSize: 14
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        radius: 10
        color: control.enabled
            ? (
                control.down
                    ? (control.theme && control.theme.buttonPressed !== undefined ? control.theme.buttonPressed : control.fallbackButtonPressed)
                    : control.hovered
                        ? (control.theme && control.theme.buttonHover !== undefined ? control.theme.buttonHover : control.fallbackButtonHover)
                        : (control.theme && control.theme.buttonBg !== undefined ? control.theme.buttonBg : control.fallbackButtonBg)
            )
            : "#525866"
        border.width: 1
        border.color: control.enabled
            ? (control.theme && control.theme.buttonBorder !== undefined ? control.theme.buttonBorder : control.fallbackButtonBorder)
            : "#454c5a"
    }
}
