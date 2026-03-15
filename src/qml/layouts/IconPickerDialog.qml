import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Popup {
    id: root

    required property var theme
    required property var backend
    required property var hostWindow

    parent: Overlay.overlay
    modal: true
    focus: true
    width: Math.min(hostWindow.width - 80, 560)
    height: Math.min(hostWindow.height - 120, 620)
    anchors.centerIn: parent
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 0

    function openForSelection() {
        iconSearchField.text = ""
        if (root.backend) {
            root.backend.startIconIndex()
            root.backend.setIconSearchQuery("")
        }
        open()
    }

    background: Rectangle {
        radius: 18
        color: root.theme.surfaceRight
        border.width: 1
        border.color: root.theme.borderStrong
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16

        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Label {
                    text: "Change Icon"
                    color: root.theme.textPrimary
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                }

                Label {
                    text: "Pick an image file or choose a system icon name."
                    color: root.theme.textSecondary
                    font.pixelSize: 13
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 18

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 64
                Layout.preferredHeight: 64
                radius: 18
                color: Qt.lighter(root.theme.surfaceRaised, 1.04)
                border.width: 1
                border.color: root.theme.borderStrong

                Image {
                    anchors.centerIn: parent
                    width: 32
                    height: 32
                    source: "image://desktopicons/" + encodeURIComponent(root.backend ? (root.backend.selectedEntry.icon || "application-x-executable") : "application-x-executable") + "?rev=" + (root.backend ? root.backend.iconRevision : 0)
                    fillMode: Image.PreserveAspectFit
                }
            }

            AppButton {
                theme: root.theme
                text: "Use Image File"
                onClicked: {
                    root.close()
                    if (root.backend)
                        root.backend.chooseIconFile()
                }
            }
        }

        SearchField {
            id: iconSearchField
            theme: root.theme
            Layout.fillWidth: true
            placeholderText: "Search system icons..."
            onTextChanged: if (root.backend) root.backend.setIconSearchQuery(text)
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 16
            color: root.theme.surfaceLeft
            border.width: 1
            border.color: root.theme.borderStrong

            GridView {
                objectName: "iconGrid"
                anchors.fill: parent
                anchors.margins: 12
                clip: true
                cellWidth: 108
                cellHeight: 102
                model: root.backend ? root.backend.iconNameModel : null

                delegate: AppTileButton {
                    required property string name
                    required property string preview

                    theme: root.theme
                    width: GridView.view.cellWidth - 12
                    height: GridView.view.cellHeight - 10
                    radius: 12
                    backgroundColor: "transparent"
                    hoverBackgroundColor: Qt.lighter(root.theme.surfaceRaised, 1.08)
                    pressedBackgroundColor: Qt.lighter(root.theme.surfaceRaised, 1.16)
                    outlineWidth: 0
                    hoverOutlineWidth: 1
                    outlineColor: "transparent"
                    hoverOutlineColor: root.theme.borderSoft

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 46
                            Layout.preferredHeight: 46
                            radius: 14
                            color: Qt.lighter(theme.surfaceRaised, 1.04)
                            border.width: 1
                            border.color: theme.borderStrong

                            Image {
                                anchors.centerIn: parent
                                width: 24
                                height: 24
                                source: "image://desktopicons/" + encodeURIComponent(preview || "application-x-executable") + "?rev=" + (root.backend ? root.backend.iconRevision : 0)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: true
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: name
                            color: theme.textPrimary
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            wrapMode: Text.Wrap
                            font.pixelSize: 12
                        }
                    }

                    onClicked: {
                        if (root.backend && name.length > 0)
                            root.backend.applyIconName(name)
                        root.close()
                    }
                }

                ScrollBar.vertical: ScrollBar { }
            }
        }
    }

    AppTileButton {
        theme: root.theme
        width: 32
        height: 32
        radius: 10
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 10
        anchors.rightMargin: 10
        backgroundColor: root.theme.surfaceLeft
        hoverBackgroundColor: Qt.lighter(root.theme.surfaceLeft, 1.14)
        pressedBackgroundColor: Qt.darker(root.theme.surfaceLeft, 1.08)
        outlineWidth: 1
        hoverOutlineWidth: 1
        outlineColor: Qt.lighter(root.theme.borderSoft, 1.45)
        hoverOutlineColor: Qt.lighter(root.theme.borderSoft, 1.75)
        onClicked: root.close()

        Image {
            anchors.centerIn: parent
            width: 16
            height: 16
            source: Qt.resolvedUrl("../icons/close.svg")
            fillMode: Image.PreserveAspectFit
        }
    }
}
