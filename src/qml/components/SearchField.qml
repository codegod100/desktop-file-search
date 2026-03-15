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

    color: theme.inkStrong
    placeholderTextColor: theme.inkSoft

    background: Rectangle {
        radius: 18
        color: field.theme.leftCard
        border.width: 1
        border.color: field.activeFocus ? field.theme.accent : field.theme.leftPanelBorder
    }
}
