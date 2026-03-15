import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Rectangle {
    id: root

    required property var theme
    required property var backend

    SplitView.preferredWidth: 500
    SplitView.minimumWidth: 360
    radius: 28
    color: root.theme.surfaceLeft
    border.width: 1
    border.color: root.theme.borderStrong

    function focusSearch() {
        searchField.forceActiveFocus()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            Label {
                text: root.backend ? root.backend.statusText : "Starting..."
                font.pixelSize: 20
                font.weight: Font.DemiBold
                color: root.theme.textPrimary
            }

            Label {
                text: "Search installed launchers and inspect desktop-entry metadata."
                color: root.theme.textSecondary
                font.pixelSize: 13
            }
        }

        SearchField {
            id: searchField
            theme: root.theme
            Layout.fillWidth: true
            placeholderText: "Search desktop files..."
            onTextChanged: if (root.backend) root.backend.setQuery(text)
        }

        BusyIndicator {
            running: root.backend ? root.backend.scanning : false
            visible: running
            Layout.alignment: Qt.AlignHCenter
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 22
            color: Qt.lighter(root.theme.surfaceLeft, 1.08)
            border.width: 1
            border.color: root.theme.borderStrong

            ListView {
                id: resultsView
                objectName: "resultsView"
                anchors.fill: parent
                anchors.margins: 10
                clip: true
                spacing: 10
                model: root.backend ? root.backend.entryModel : null
                maximumFlickVelocity: 11000
                flickDeceleration: 1200

                delegate: ResultDelegate {
                    theme: root.theme
                    current: ListView.isCurrentItem
                    onActivated: {
                        resultsView.currentIndex = index
                        if (root.backend)
                            root.backend.selectEntry(index)
                    }
                }

                ScrollBar.vertical: ScrollBar { }

                WheelHandler {
                    onWheel: function(event) {
                        const isTouchpad = event.pixelDelta.y !== 0
                        const delta = isTouchpad ? event.pixelDelta.y : event.angleDelta.y
                        if (!delta)
                            return
                        const maxY = Math.max(0, resultsView.contentHeight - resultsView.height)
                        const scaled = isTouchpad ? delta * 140.0 : delta * 8.5
                        const nextY = Math.max(0, Math.min(maxY, resultsView.contentY - scaled))
                        resultsView.contentY = nextY
                        if (root.backend) {
                            root.backend.recordWheelDebug(
                                "results",
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
        }
    }
}
