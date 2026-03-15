import QtQuick
import QtQuick.Controls

TextField {
    id: field

    required property var theme

    selectByMouse: true
    font.pixelSize: 15
    leftPadding: 16
    rightPadding: 16
    topPadding: 14
    bottomPadding: 14

    color: theme.textPrimary
    placeholderTextColor: Qt.darker(theme.textSecondary, 1.25)

    background: Rectangle {
        radius: 18
        color: field.theme.surfaceRaised
        border.width: 1
        border.color: field.activeFocus ? Qt.darker(field.theme.accentPrimary, 1.08) : field.theme.borderStrong
    }
}
