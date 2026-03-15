import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root

    required property var theme
    required property var backend
    required property var iconPicker

    ColumnLayout {
        anchors.fill: parent
        spacing: 18

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            AppTileButton {
                theme: root.theme
                Layout.preferredWidth: 84
                Layout.preferredHeight: 84
                radius: 0
                backgroundColor: Qt.lighter(root.theme.surfaceRaised, 1.04)
                hoverBackgroundColor: Qt.lighter(root.theme.surfaceRaised, 1.08)
                pressedBackgroundColor: Qt.lighter(root.theme.surfaceRaised, 1.16)
                outlineWidth: 0
                hoverOutlineWidth: 0
                outlineColor: "transparent"
                hoverOutlineColor: "transparent"
                onClicked: if (root.iconPicker) root.iconPicker.openForSelection()

                Image {
                    anchors.centerIn: parent
                    width: 46
                    height: 46
                    source: "image://desktopicons/" + encodeURIComponent(root.backend ? (root.backend.selectedEntry.icon || "application-x-executable") : "application-x-executable") + "?rev=" + (root.backend ? root.backend.iconRevision : 0)
                    fillMode: Image.PreserveAspectFit
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: root.theme.borderStrong
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    width: 1
                    color: root.theme.borderStrong
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    width: 1
                    height: parent.height - badge.height
                    color: root.theme.borderStrong
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    height: 1
                    width: parent.width - badge.width
                    color: root.theme.borderStrong
                }

                AppSurface {
                    id: badge
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: 0
                    anchors.bottomMargin: 0
                    width: 22
                    height: 22
                    topLeftRadius: 10
                    topRightRadius: 0
                    bottomLeftRadius: 0
                    bottomRightRadius: 0
                    backgroundColor: Qt.lighter(root.theme.surfaceRight, 1.12)
                    outlineWidth: 1
                    outlineColor: root.theme.borderStrong

                    Rectangle {
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        width: 1
                        antialiasing: false
                        color: badge.backgroundColor
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        antialiasing: false
                        color: badge.backgroundColor
                    }

                    Image {
                        anchors.centerIn: parent
                        width: 12
                        height: 12
                        source: Qt.resolvedUrl("../icons/image-update.svg")
                        fillMode: Image.PreserveAspectFit
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 5

                Label {
                    text: root.backend ? (root.backend.selectedEntry.name || "") : ""
                    color: root.theme.textPrimary
                    font.pixelSize: 30
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    AppSurface {
                        Layout.fillWidth: true
                        implicitHeight: pathField.implicitHeight + 20
                        backgroundColor: root.theme.surfaceLeft
                        outlineColor: root.theme.borderStrong

                        TextEdit {
                            id: pathField
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.topMargin: 10
                            anchors.bottomMargin: 10
                            anchors.rightMargin: 36
                            readOnly: true
                            selectByMouse: true
                            selectByKeyboard: true
                            text: root.backend ? (root.backend.selectedEntry.path || "") : ""
                            color: root.theme.textSecondary
                            wrapMode: TextEdit.WrapAnywhere
                            font.pixelSize: 13
                        }

                        AppTileButton {
                            theme: root.theme
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24
                            height: 24
                            radius: 0
                            backgroundColor: Qt.lighter(root.theme.surfaceRight, 1.12)
                            hoverBackgroundColor: Qt.lighter(root.theme.surfaceRight, 1.16)
                            pressedBackgroundColor: Qt.darker(root.theme.surfaceRight, 1.08)
                            outlineWidth: 0
                            hoverOutlineWidth: 0
                            outlineColor: "transparent"
                            hoverOutlineColor: "transparent"
                            onClicked: {
                                pathField.selectAll()
                                pathField.copy()
                                pathField.deselect()
                            }

                            Image {
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                source: Qt.resolvedUrl("../icons/copy.svg")
                                fillMode: Image.PreserveAspectFit
                            }
                        }
                    }
                }
            }
        }

        ScrollView {
            id: detailsScroll
            objectName: "detailsScroll"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            Column {
                width: detailsScroll.availableWidth
                spacing: 14

                DetailCard {
                    theme: root.theme
                    width: parent.width
                    title: "Desktop Entry"

                    ColumnLayout {
                        width: parent.width
                        spacing: 10

                        DetailRow { theme: root.theme; label: "Type"; value: root.backend ? (root.backend.selectedEntry.desktop_type || "") : "" }
                        DetailRow { theme: root.theme; label: "Comment"; value: root.backend ? (root.backend.selectedEntry.comment || "") : "" }
                        DetailRow { theme: root.theme; label: "Categories"; value: root.backend ? (root.backend.selectedEntry.categories || "") : "" }
                        DetailRow { theme: root.theme; label: "Mime Types"; value: root.backend ? (root.backend.selectedEntry.mimetypes || "") : "" }
                        DetailRow { theme: root.theme; label: "Terminal"; value: root.backend ? (root.backend.selectedEntry.terminal ? "Yes" : "No") : "" }
                        DetailRow { theme: root.theme; label: "Startup Notify"; value: root.backend ? (root.backend.selectedEntry.startup_notify ? "Yes" : "No") : "" }
                    }
                }

                DetailCard {
                    theme: root.theme
                    width: parent.width
                    title: "Package"

                    Loader {
                        width: parent.width
                        active: true
                        sourceComponent: root.backend && root.backend.detailLoading ? packageLoadingState : packageReadyState
                    }
                }

                DetailCard {
                    theme: root.theme
                    width: parent.width
                    title: "Exec"

                    AppSurface {
                        width: parent.width
                        implicitHeight: execRow.implicitHeight + 20
                        backgroundColor: root.theme.surfaceLeft
                        outlineColor: root.theme.borderStrong

                        RowLayout {
                            id: execRow
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            TextEdit {
                                id: execLabel
                                Layout.fillWidth: true
                                readOnly: true
                                selectByMouse: true
                                selectByKeyboard: true
                                    activeFocusOnPress: false
                                    cursorVisible: false
                                    text: root.backend ? (root.backend.selectedEntry.exec || "") : ""
                                    color: root.theme.textPrimary
                                wrapMode: TextEdit.WrapAnywhere
                                font.pixelSize: 13
                                font.family: "monospace"
                            }

                            AppTileButton {
                                theme: root.theme
                                Layout.alignment: Qt.AlignTop
                                width: 24
                                height: 24
                                radius: 0
                                backgroundColor: Qt.lighter(root.theme.surfaceRight, 1.12)
                                hoverBackgroundColor: Qt.lighter(root.theme.surfaceRight, 1.16)
                                pressedBackgroundColor: Qt.darker(root.theme.surfaceRight, 1.08)
                                outlineWidth: 0
                                hoverOutlineWidth: 0
                                outlineColor: "transparent"
                                hoverOutlineColor: "transparent"
                                onClicked: {
                                    execLabel.selectAll()
                                    execLabel.copy()
                                    execLabel.deselect()
                                }

                                Image {
                                    anchors.centerIn: parent
                                    width: 16
                                    height: 16
                                    source: Qt.resolvedUrl("../icons/copy.svg")
                                    fillMode: Image.PreserveAspectFit
                                }
                            }
                        }
                    }
                }
            }

            WheelHandler {
                onWheel: function(event) {
                    const flickable = detailsScroll.contentItem
                    if (!flickable)
                        return
                    const isTouchpad = event.pixelDelta.y !== 0
                    const delta = isTouchpad ? event.pixelDelta.y : event.angleDelta.y
                    if (!delta)
                        return
                    const maxY = Math.max(0, flickable.contentHeight - flickable.height)
                    const scaled = isTouchpad ? delta * 140.0 : delta * 8.5
                    const nextY = Math.max(0, Math.min(maxY, flickable.contentY - scaled))
                    flickable.contentY = nextY
                    if (root.backend) {
                        root.backend.recordWheelDebug(
                            "details",
                            event.pixelDelta.y,
                            event.angleDelta.y,
                            scaled,
                            nextY,
                            maxY
                        )
                    }
                    if (isTouchpad)
                        event.accepted = true
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            AppButton {
                theme: root.theme
                surfaceColor: root.theme.surfaceRight
                Layout.preferredWidth: 210
                text: "Open in Default Editor"
                onClicked: if (root.backend) root.backend.openSelected()
            }

            AppButton {
                theme: root.theme
                surfaceColor: root.theme.surfaceRight
                Layout.preferredWidth: 190
                text: "Choose Application..."
                onClicked: if (root.backend) root.backend.chooseEditor()
            }
        }
    }

    Component {
        id: packageLoadingState

        Item {
            width: parent ? parent.width : 0
            implicitHeight: 72

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0

                BusyIndicator {
                    running: true
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }

    Component {
        id: packageReadyState

        ColumnLayout {
            width: parent ? parent.width : 0
            spacing: 10

            DetailRow { theme: root.theme; label: "Name"; value: root.backend ? (root.backend.selectedEntry.packageName || "Not available") : "Not available" }
            DetailRow { theme: root.theme; label: "Version"; value: root.backend ? (root.backend.selectedEntry.packageVersion || "") : "" }
            DetailRow { theme: root.theme; label: "Description"; value: root.backend ? (root.backend.selectedEntry.packageDescription || "") : "" }
            DetailRow { theme: root.theme; label: "License"; value: root.backend ? (root.backend.selectedEntry.packageLicense || "") : "" }
            DetailRow { theme: root.theme; label: "Depends On"; value: root.backend ? (root.backend.selectedEntry.packageDepends || "") : "" }

            AppButton {
                theme: root.theme
                surfaceColor: root.theme.surfaceLeft
                visible: !!(root.backend && root.backend.selectedEntry.packageUrl)
                width: implicitWidth
                text: "Open Package URL"
                onClicked: if (root.backend) root.backend.openPackageUrl()
            }
        }
    }
}
