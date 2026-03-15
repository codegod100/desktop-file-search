import QtQuick

Rectangle {
    id: control

    required property var theme
    property color backgroundColor: "transparent"
    property color hoverBackgroundColor: backgroundColor
    property color pressedBackgroundColor: hoverBackgroundColor
    property color outlineColor: "transparent"
    property color hoverOutlineColor: outlineColor
    property int outlineWidth: 0
    property int hoverOutlineWidth: outlineWidth
    property real contentMargin: 0
    default property alias buttonContent: content.data

    signal clicked()

    color: mouseArea.pressed ? pressedBackgroundColor : mouseArea.containsMouse ? hoverBackgroundColor : backgroundColor
    border.width: mouseArea.containsMouse || mouseArea.pressed ? hoverOutlineWidth : outlineWidth
    border.color: mouseArea.containsMouse || mouseArea.pressed ? hoverOutlineColor : outlineColor

    Item {
        id: content
        anchors.fill: parent
        anchors.margins: control.contentMargin
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: control.clicked()
    }
}
