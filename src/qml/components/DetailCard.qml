import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Frame {
    id: card

    required property string title
    required property var theme
    default property alias cardContent: body.data

    padding: 16

    background: Rectangle {
        radius: 22
        color: card.theme.rightCard
        border.width: 1
        border.color: card.theme.rightCardBorder
    }

    ColumnLayout {
        id: body
        anchors.fill: parent
        spacing: 12

        Label {
            text: card.title
            color: card.theme.rightText
            font.pixelSize: 20
            font.weight: Font.DemiBold
        }
    }
}
