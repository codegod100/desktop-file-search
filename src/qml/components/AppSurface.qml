import QtQuick

Rectangle {
    id: control

    property color backgroundColor: "transparent"
    property color outlineColor: "transparent"
    property int outlineWidth: 1
    property real contentMargin: 0
    default property alias surfaceContent: content.data

    color: backgroundColor
    radius: 0
    border.width: outlineWidth
    border.color: outlineColor

    Item {
        id: content
        anchors.fill: parent
        anchors.margins: control.contentMargin
    }
}
