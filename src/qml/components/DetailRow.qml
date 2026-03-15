import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: row

    required property string label
    required property string value
    required property var theme

    visible: value.length > 0
    spacing: 4

    Label {
        text: row.label
        color: Qt.darker(row.theme.textSecondary, 1.3)
        font.pixelSize: 11
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.6
    }

    Label {
        text: row.value
        color: row.theme.textPrimary
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }
}
