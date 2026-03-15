import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root

    required property int index
    required property string name
    required property string icon
    required property string path
    required property string comment
    required property var theme
    required property bool current

    signal activated()

    width: ListView.view.width
    height: content.implicitHeight + 26
    radius: 20
    color: current
        ? Qt.darker(Qt.lighter(theme.surfaceRaised, 1.16), 1.06)
        : mouseArea.containsMouse
            ? Qt.lighter(Qt.lighter(theme.surfaceLeft, 1.08), 1.08)
            : Qt.lighter(theme.surfaceLeft, 1.08)
    border.width: current ? 2 : 1
    border.color: current
        ? theme.accentPrimary
        : theme.borderStrong

    RowLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 14
        spacing: 14

        Rectangle {
            Layout.preferredWidth: 56
            Layout.preferredHeight: 56
            radius: 18
            color: root.current ? Qt.darker(Qt.lighter(theme.surfaceRaised, 1.16), 1.06) : Qt.darker(theme.surfaceRight, 1.15)

            Image {
                anchors.centerIn: parent
                width: 32
                height: 32
                source: "image://desktopicons/" + encodeURIComponent(root.icon || "application-x-executable") + "?rev=" + (backend ? backend.iconRevision : 0)
                fillMode: Image.PreserveAspectFit
                smooth: true
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Label {
                text: root.name
                color: theme.textPrimary
                font.pixelSize: 16
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Label {
                visible: root.comment.length > 0
                text: root.comment
                color: theme.textPrimary
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Label {
                text: root.path
                color: theme.textSecondary
                font.pixelSize: 12
                elide: Text.ElideMiddle
                Layout.fillWidth: true
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.activated()
    }
}
