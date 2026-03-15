import QtQuick
import QtQuick.Controls

TextField {
    id: field

    required property var theme
    readonly property color focusBorderColor: "#4f86c6"

    selectByMouse: true
    font.pixelSize: 15
    leftPadding: 16
    rightPadding: 16
    topPadding: 14
    bottomPadding: 14

    color: theme.textPrimary
    placeholderTextColor: Qt.darker(theme.textSecondary, 1.25)

    background: AppSurface {
        backgroundColor: field.theme.surfaceRaised
        outlineColor: field.activeFocus ? field.focusBorderColor : field.theme.borderStrong
    }
}
