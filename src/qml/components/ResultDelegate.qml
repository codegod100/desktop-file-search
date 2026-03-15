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

    readonly property color fallbackLeftCard: "#444a58"
    readonly property color fallbackLeftCardHover: "#4b5160"
    readonly property color fallbackLeftCardSelected: "#505767"
    readonly property color fallbackLeftCardSelectedBorder: "#5294e2"
    readonly property color fallbackLeftPanelBorder: "#20242b"
    readonly property color fallbackAccentSoft: "#3b4252"
    readonly property color fallbackInkStrong: "#eff0f1"
    readonly property color fallbackInkMuted: "#c0c5ce"
    readonly property color fallbackInkSoft: "#9aa3ad"

    signal activated()

    width: ListView.view.width
    height: content.implicitHeight + 26
    radius: 20
    color: current
        ? (theme && theme.leftCardSelected !== undefined ? theme.leftCardSelected : fallbackLeftCardSelected)
        : mouseArea.containsMouse
            ? (theme && theme.leftCardHover !== undefined ? theme.leftCardHover : fallbackLeftCardHover)
            : (theme && theme.leftCard !== undefined ? theme.leftCard : fallbackLeftCard)
    border.width: current ? 2 : 1
    border.color: current
        ? (theme && theme.leftCardSelectedBorder !== undefined ? theme.leftCardSelectedBorder : fallbackLeftCardSelectedBorder)
        : (theme && theme.leftPanelBorder !== undefined ? theme.leftPanelBorder : fallbackLeftPanelBorder)

    RowLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 14
        spacing: 14

        Rectangle {
            Layout.preferredWidth: 56
            Layout.preferredHeight: 56
            radius: 18
            color: root.current ? "#5c6374" : (root.theme && root.theme.accentSoft !== undefined ? root.theme.accentSoft : fallbackAccentSoft)

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
                color: root.theme && root.theme.inkStrong !== undefined ? root.theme.inkStrong : fallbackInkStrong
                font.pixelSize: 16
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Label {
                visible: root.comment.length > 0
                text: root.comment
                color: root.theme && root.theme.inkMuted !== undefined ? root.theme.inkMuted : fallbackInkMuted
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Label {
                text: root.path
                color: root.theme && root.theme.inkSoft !== undefined ? root.theme.inkSoft : fallbackInkSoft
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
