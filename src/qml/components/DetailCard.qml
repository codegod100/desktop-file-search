import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Frame {
    id: card

    required property string title
    required property var theme
    default property alias cardContent: body.data

    padding: 16

    background: AppSurface {
        backgroundColor: card.theme.surfaceLeft
        outlineColor: card.theme.borderStrong
    }

    ColumnLayout {
        id: body
        anchors.fill: parent
        spacing: 12

        Label {
            text: card.title
            color: card.theme.textPrimary
            font.pixelSize: 20
            font.weight: Font.DemiBold
        }
    }
}
