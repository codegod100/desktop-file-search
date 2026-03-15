import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: row

    required property string label
    required property string value
    required property var theme
    readonly property color fallbackRightSoft: "#8e98a4"
    readonly property color fallbackRightText: "#eff0f1"

    visible: value.length > 0
    spacing: 4

    Label {
        text: row.label
        color: row.theme && row.theme.rightSoft !== undefined ? row.theme.rightSoft : row.fallbackRightSoft
        font.pixelSize: 11
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.6
    }

    Label {
        text: row.value
        color: row.theme && row.theme.rightText !== undefined ? row.theme.rightText : row.fallbackRightText
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }
}
