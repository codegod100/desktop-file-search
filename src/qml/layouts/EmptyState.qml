import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root

    required property var theme

    anchors.centerIn: parent
    width: Math.min(parent.width - 80, 460)
    spacing: 16

    Label {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: "Select a desktop file"
        color: root.theme.textPrimary
        font.pixelSize: 30
        font.weight: Font.DemiBold
    }

    Label {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: "Choose an entry from the list to inspect metadata, package ownership, and launch details."
        color: root.theme.textSecondary
        font.pixelSize: 15
    }
}
