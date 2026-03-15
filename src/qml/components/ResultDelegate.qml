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
    readonly property int iconPendingRevision: backend ? backend.iconPendingRevision : 0

    signal activated()

    width: ListView.view.width
    height: content.implicitHeight + 26
    radius: 0
    readonly property color selectedFill: Qt.darker(Qt.lighter(theme.surfaceRaised, 1.12), 1.12)
    color: current
        ? selectedFill
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
            radius: 0
            color: Qt.lighter(theme.surfaceRaised, 1.04)
            border.width: 1
            border.color: theme.borderStrong

            AsyncIcon {
                anchors.centerIn: parent
                width: 32
                height: 32
                iconName: root.icon || "application-x-executable"
                revision: backend ? backend.iconRevision : 0
                loading: {
                    root.iconPendingRevision
                    return backend ? backend.isIconPending(root.icon || "application-x-executable") : false
                }
                placeholderColor: Qt.lighter(theme.surfaceRaised, 1.1)
                accentColor: theme.accentPrimary
                spinnerColor: theme.textPrimary
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
