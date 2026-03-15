import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "components"

ApplicationWindow {
    id: window
    width: 1240
    height: 820
    minimumWidth: 980
    minimumHeight: 680
    visible: true
    title: "Desktop File Search"
    color: "#2a2f34"

    readonly property var appBackend: backend
    readonly property bool hasSelection: !!(appBackend && appBackend.selectedEntry && appBackend.selectedEntry.path)

    Component.onCompleted: Qt.callLater(function() {
        searchField.forceActiveFocus()
    })
    
    QtObject {
        id: palette
        readonly property color bgTop: "#31363b"
        readonly property color bgBottom: "#2a2f34"
        readonly property color leftPanel: "#383c4a"
        readonly property color leftPanelBorder: "#20242b"
        readonly property color leftSubtle: "#404552"
        readonly property color leftCard: "#444a58"
        readonly property color leftCardHover: "#4b5160"
        readonly property color leftCardSelected: "#505767"
        readonly property color leftCardSelectedBorder: "#5294e2"
        readonly property color inkStrong: "#eff0f1"
        readonly property color inkMuted: "#c0c5ce"
        readonly property color inkSoft: "#9aa3ad"
        readonly property color accent: "#5294e2"
        readonly property color accentSoft: "#3b4252"
        readonly property color rightPanel: "#2f343f"
        readonly property color rightPanelBorder: "#1f2329"
        readonly property color rightCard: "#383c4a"
        readonly property color rightCardBorder: "#4b5160"
        readonly property color rightIconWell: "#454c5c"
        readonly property color rightText: "#eff0f1"
        readonly property color rightMuted: "#bcc2cc"
        readonly property color rightSoft: "#8e98a4"
        readonly property color buttonBg: "#596071"
        readonly property color buttonHover: "#646c7f"
        readonly property color buttonPressed: "#4d5565"
        readonly property color buttonBorder: "#2a2f38"
        readonly property color buttonText: "#eff0f1"
        readonly property color iconButtonBg: "#2f343f"
        readonly property color iconButtonHover: "#3b4250"
        readonly property color iconButtonPressed: "#262b34"
        readonly property color iconButtonBorder: "#596272"
        readonly property color iconButtonIdleBorder: "#00000000"
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: palette.bgTop }
            GradientStop { position: 0.55; color: "#2f343f" }
            GradientStop { position: 1.0; color: palette.bgBottom }
        }
    }

    SplitView {
        anchors.fill: parent
        anchors.margins: 22
        spacing: 18
        handle: Item {
            implicitWidth: 0
            implicitHeight: 0
        }

        Rectangle {
            SplitView.preferredWidth: 500
            SplitView.minimumWidth: 360
            radius: 28
            color: palette.leftPanel
            border.width: 1
            border.color: palette.leftPanelBorder

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 16

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Label {
                        text: appBackend ? appBackend.statusText : "Starting..."
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                        color: palette.inkStrong
                    }

                    Label {
                        text: "Search installed launchers and inspect desktop-entry metadata."
                        color: palette.inkMuted
                        font.pixelSize: 13
                    }
                }

                SearchField {
                    id: searchField
                    theme: palette
                    Layout.fillWidth: true
                    placeholderText: "Search desktop files..."
                    onTextChanged: if (appBackend) appBackend.setQuery(text)
                }

                BusyIndicator {
                    running: appBackend ? appBackend.scanning : false
                    visible: running
                    Layout.alignment: Qt.AlignHCenter
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 22
                    color: palette.leftSubtle
                    border.width: 1
                    border.color: palette.leftPanelBorder

                    ListView {
                        id: resultsView
                        objectName: "resultsView"
                        anchors.fill: parent
                        anchors.margins: 10
                        clip: true
                        spacing: 10
                        model: appBackend ? appBackend.entryModel : null
                        maximumFlickVelocity: 11000
                        flickDeceleration: 1200

                        delegate: ResultDelegate {
                            theme: palette
                            current: ListView.isCurrentItem
                            onActivated: {
                                resultsView.currentIndex = index
                                if (appBackend) appBackend.selectEntry(index)
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
                                const nextY = Math.max(
                                    0,
                                    Math.min(
                                        maxY,
                                        resultsView.contentY - scaled
                                    )
                                )
                                resultsView.contentY = nextY
                                if (appBackend) appBackend.recordWheelDebug(
                                    "results",
                                    event.pixelDelta.y,
                                    event.angleDelta.y,
                                    scaled,
                                    nextY,
                                    maxY
                                )
                                if (isTouchpad)
                                    event.accepted = true
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            SplitView.fillWidth: true
            SplitView.minimumWidth: 460
            radius: 28
            color: palette.rightPanel
            border.width: 1
            border.color: palette.rightPanelBorder

            Item {
                anchors.fill: parent
                anchors.margins: 24

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 18
                    visible: window.hasSelection

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Rectangle {
                            id: headerIconBox
                            Layout.preferredWidth: 84
                            Layout.preferredHeight: 84
                            radius: 26
                            color: palette.rightIconWell

                            Image {
                                anchors.centerIn: parent
                                width: 46
                                height: 46
                                source: "image://desktopicons/" + encodeURIComponent(appBackend ? (appBackend.selectedEntry.icon || "application-x-executable") : "application-x-executable") + "?rev=" + (appBackend ? appBackend.iconRevision : 0)
                                fillMode: Image.PreserveAspectFit
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.rightMargin: 6
                                anchors.bottomMargin: 6
                                width: 22
                                height: 22
                                radius: 11
                                color: "#223246"
                                border.width: 1
                                border.color: palette.rightCardBorder

                                Text {
                                    anchors.centerIn: parent
                                    text: "+"
                                    color: palette.rightText
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (appBackend) {
                                        iconSearchField.text = ""
                                        appBackend.startIconIndex()
                                        appBackend.setIconSearchQuery("")
                                        iconPicker.open()
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 5

                            Label {
                                text: appBackend ? (appBackend.selectedEntry.name || "") : ""
                                color: palette.rightText
                                font.pixelSize: 30
                                font.weight: Font.DemiBold
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: pathField.implicitHeight + 20
                                    radius: 12
                                    color: "#263442"
                                    border.width: 1
                                    border.color: palette.rightCardBorder

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
                                        text: appBackend ? (appBackend.selectedEntry.path || "") : ""
                                        color: palette.rightMuted
                                        wrapMode: TextEdit.WrapAnywhere
                                        font.pixelSize: 13
                                    }

                                    ToolButton {
                                        id: copyButton
                                        anchors.right: parent.right
                                        anchors.rightMargin: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 24
                                        height: 24
                                        hoverEnabled: true
                                        padding: 0
                                        ToolTip.visible: hovered
                                        ToolTip.text: "Copy path"
                                        onClicked: {
                                            pathField.selectAll()
                                            pathField.copy()
                                            pathField.deselect()
                                        }

                                        background: Rectangle {
                                            radius: 6
                                            color: copyButton.down ? palette.iconButtonPressed : copyButton.hovered ? palette.iconButtonHover : "#31465d"
                                            border.width: 1
                                            border.color: copyButton.hovered || copyButton.down ? palette.iconButtonBorder : "#65788c"
                                        }

                                        contentItem: Item {
                                            implicitWidth: 18
                                            implicitHeight: 18

                                            Rectangle {
                                                width: 9
                                                height: 11
                                                radius: 2
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.horizontalCenterOffset: -2
                                                anchors.verticalCenterOffset: 1
                                                color: "transparent"
                                                border.width: 1
                                                border.color: "#f3f6fb"
                                            }

                                            Rectangle {
                                                width: 9
                                                height: 11
                                                radius: 2
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.horizontalCenterOffset: 2
                                                anchors.verticalCenterOffset: -2
                                                color: "transparent"
                                                border.width: 1
                                                border.color: "#f3f6fb"
                                            }
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
                                theme: palette
                                width: parent.width
                                title: "Desktop Entry"

                                ColumnLayout {
                                    width: parent.width
                                    spacing: 10

                                    DetailRow { theme: palette; label: "Type"; value: appBackend ? (appBackend.selectedEntry.desktop_type || "") : "" }
                                    DetailRow { theme: palette; label: "Comment"; value: appBackend ? (appBackend.selectedEntry.comment || "") : "" }
                                    DetailRow { theme: palette; label: "Categories"; value: appBackend ? (appBackend.selectedEntry.categories || "") : "" }
                                    DetailRow { theme: palette; label: "Mime Types"; value: appBackend ? (appBackend.selectedEntry.mimetypes || "") : "" }
                                    DetailRow { theme: palette; label: "Terminal"; value: appBackend ? (appBackend.selectedEntry.terminal ? "Yes" : "No") : "" }
                                    DetailRow { theme: palette; label: "Startup Notify"; value: appBackend ? (appBackend.selectedEntry.startup_notify ? "Yes" : "No") : "" }
                                }
                            }

                            DetailCard {
                                theme: palette
                                width: parent.width
                                title: "Package"

                                Loader {
                                    width: parent.width
                                    active: true
                                    sourceComponent: appBackend && appBackend.detailLoading ? packageLoadingState : packageReadyState
                                }
                            }

                            DetailCard {
                                theme: palette
                                width: parent.width
                                title: "Exec"

                                Rectangle {
                                    width: parent.width
                                    implicitHeight: execRow.implicitHeight + 20
                                    radius: 12
                                    color: "#263442"
                                    border.width: 1
                                    border.color: palette.rightCardBorder

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
                                            text: appBackend ? (appBackend.selectedEntry.exec || "") : ""
                                            color: palette.rightText
                                            wrapMode: TextEdit.WrapAnywhere
                                            font.pixelSize: 13
                                            font.family: "monospace"
                                        }

                                        ToolButton {
                                            id: execCopyButton
                                            Layout.alignment: Qt.AlignTop
                                            width: 24
                                            height: 24
                                            hoverEnabled: true
                                            padding: 0
                                            ToolTip.visible: hovered
                                            ToolTip.text: "Copy exec"
                                            onClicked: {
                                                execLabel.selectAll()
                                                execLabel.copy()
                                                execLabel.deselect()
                                            }

                                            background: Rectangle {
                                                radius: 6
                                                color: execCopyButton.down ? palette.iconButtonPressed : execCopyButton.hovered ? palette.iconButtonHover : "#31465d"
                                                border.width: 1
                                                border.color: execCopyButton.hovered || execCopyButton.down ? palette.iconButtonBorder : "#65788c"
                                            }

                                            contentItem: Item {
                                                implicitWidth: 18
                                                implicitHeight: 18

                                                Rectangle {
                                                    width: 9
                                                    height: 11
                                                    radius: 2
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.horizontalCenterOffset: -2
                                                    anchors.verticalCenterOffset: 1
                                                    color: "transparent"
                                                    border.width: 1
                                                    border.color: "#f3f6fb"
                                                }

                                                Rectangle {
                                                    width: 9
                                                    height: 11
                                                    radius: 2
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.horizontalCenterOffset: 2
                                                    anchors.verticalCenterOffset: -2
                                                    color: "transparent"
                                                    border.width: 1
                                                    border.color: "#f3f6fb"
                                                }
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
                                const nextY = Math.max(
                                    0,
                                    Math.min(
                                        maxY,
                                        flickable.contentY - scaled
                                    )
                                )
                                flickable.contentY = nextY
                                if (appBackend) appBackend.recordWheelDebug(
                                    "details",
                                    event.pixelDelta.y,
                                    event.angleDelta.y,
                                    scaled,
                                    nextY,
                                    maxY
                                )
                                if (isTouchpad)
                                    event.accepted = true
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        AppButton {
                            theme: palette
                            Layout.preferredWidth: 210
                            text: "Open in Default Editor"
                            onClicked: if (appBackend) appBackend.openSelected()
                        }

                        AppButton {
                            theme: palette
                            Layout.preferredWidth: 190
                            text: "Choose Application..."
                            onClicked: if (appBackend) appBackend.chooseEditor()
                        }
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 80, 460)
                    spacing: 16
                    visible: !window.hasSelection

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 96
                        height: 96
                        radius: 32
                        color: palette.rightIconWell

                        Rectangle {
                            anchors.centerIn: parent
                            width: 38
                            height: 38
                            radius: 19
                            color: palette.accent
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: "Select a desktop file"
                        color: palette.rightText
                        font.pixelSize: 30
                        font.weight: Font.DemiBold
                    }

                    Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: "Choose an entry from the list to inspect metadata, package ownership, and launch details."
                        color: palette.rightMuted
                        font.pixelSize: 15
                    }
                }

                Popup {
                    id: iconPicker
                    parent: Overlay.overlay
                    modal: true
                    focus: true
                    width: Math.min(window.width - 80, 560)
                    height: Math.min(window.height - 120, 620)
                    anchors.centerIn: parent
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                    padding: 0

                    background: Rectangle {
                        radius: 18
                        color: "#2b313b"
                        border.width: 1
                        border.color: palette.rightCardBorder
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 14

                        RowLayout {
                            Layout.fillWidth: true

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Label {
                                    text: "Change Icon"
                                    color: palette.rightText
                                    font.pixelSize: 22
                                    font.weight: Font.DemiBold
                                }

                                Label {
                                    text: "Pick an image file or choose a system icon name."
                                    color: palette.rightMuted
                                    font.pixelSize: 13
                                }
                            }

                            ToolButton {
                                id: iconPickerCloseButton
                                onClicked: iconPicker.close()
                                background: Rectangle {
                                    radius: 8
                                    color: iconPickerCloseButton.down ? palette.iconButtonPressed : iconPickerCloseButton.hovered ? palette.iconButtonHover : "transparent"
                                }
                                contentItem: Text {
                                    text: "×"
                                    color: palette.rightText
                                    font.pixelSize: 20
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Rectangle {
                                Layout.preferredWidth: 64
                                Layout.preferredHeight: 64
                                radius: 18
                                color: palette.rightIconWell

                                Image {
                                    anchors.centerIn: parent
                                    width: 36
                                    height: 36
                                    source: "image://desktopicons/" + encodeURIComponent(appBackend ? (appBackend.selectedEntry.icon || "application-x-executable") : "application-x-executable") + "?rev=" + (appBackend ? appBackend.iconRevision : 0)
                                    fillMode: Image.PreserveAspectFit
                                }
                            }

                            AppButton {
                                theme: palette
                                text: "Use Image File"
                                onClicked: {
                                    iconPicker.close()
                                    if (appBackend) appBackend.chooseIconFile()
                                }
                            }
                        }

                        TextField {
                            id: iconSearchField
                            Layout.fillWidth: true
                            placeholderText: "Search system icons..."
                            color: palette.rightText
                            placeholderTextColor: palette.inkSoft
                            onTextChanged: if (appBackend) appBackend.setIconSearchQuery(text)
                            background: Rectangle {
                                radius: 12
                                color: "#263442"
                                border.width: 1
                                border.color: palette.rightCardBorder
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 14
                            color: "#263442"
                            border.width: 1
                            border.color: palette.rightCardBorder

                            GridView {
                                id: iconGrid
                                objectName: "iconGrid"
                                anchors.fill: parent
                                anchors.margins: 8
                                clip: true
                                cellWidth: 104
                                cellHeight: 96
                                model: appBackend ? appBackend.iconNameModel : null

                                delegate: Rectangle {
                                    required property string name
                                    required property string preview

                                    width: GridView.view.cellWidth - 8
                                    height: GridView.view.cellHeight - 8
                                    radius: 10
                                    color: rowMouse.containsMouse ? "#354250" : "transparent"
                                    border.width: rowMouse.containsMouse ? 1 : 0
                                    border.color: palette && palette.rightCardBorder !== undefined ? palette.rightCardBorder : "#4b5160"

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 8

                                        Rectangle {
                                            Layout.alignment: Qt.AlignHCenter
                                            Layout.preferredWidth: 42
                                            Layout.preferredHeight: 42
                                            radius: 12
                                            color: palette && palette.rightIconWell !== undefined ? palette.rightIconWell : "#454c5c"

                                            Image {
                                                anchors.centerIn: parent
                                                width: 24
                                                height: 24
                                                source: "image://desktopicons/" + encodeURIComponent(preview || "application-x-executable") + "?rev=" + (appBackend ? appBackend.iconRevision : 0)
                                                fillMode: Image.PreserveAspectFit
                                                asynchronous: true
                                                cache: true
                                            }
                                        }

                                        Label {
                                            Layout.fillWidth: true
                                            horizontalAlignment: Text.AlignHCenter
                                            text: name
                                            color: palette && palette.rightText !== undefined ? palette.rightText : "#eff0f1"
                                            maximumLineCount: 2
                                            elide: Text.ElideRight
                                            wrapMode: Text.Wrap
                                            font.pixelSize: 12
                                        }
                                    }

                                    MouseArea {
                                        id: rowMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            if (appBackend && name.length > 0) appBackend.applyIconName(name)
                                            iconPicker.close()
                                        }
                                    }
                                }

                                ScrollBar.vertical: ScrollBar { }
                            }
                        }
                    }
                }
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

            DetailRow { theme: palette; label: "Name"; value: appBackend ? (appBackend.selectedEntry.packageName || "Not available") : "Not available" }
            DetailRow { theme: palette; label: "Version"; value: appBackend ? (appBackend.selectedEntry.packageVersion || "") : "" }
            DetailRow { theme: palette; label: "Description"; value: appBackend ? (appBackend.selectedEntry.packageDescription || "") : "" }
            DetailRow { theme: palette; label: "License"; value: appBackend ? (appBackend.selectedEntry.packageLicense || "") : "" }
            DetailRow { theme: palette; label: "Depends On"; value: appBackend ? (appBackend.selectedEntry.packageDepends || "") : "" }

            Rectangle {
                id: packageUrlButton
                visible: !!(appBackend && appBackend.selectedEntry.packageUrl)
                implicitWidth: Math.max(138, packageUrlLabel.implicitWidth + 36)
                implicitHeight: 34
                radius: 2
                color: packageUrlMouse.pressed ? "#4d5565" : packageUrlMouse.containsMouse ? "#646c7f" : "#596071"
                border.width: 1
                border.color: "#2a2f38"

                Text {
                    id: packageUrlLabel
                    anchors.centerIn: parent
                    text: "Open Package URL"
                    color: "#eff0f1"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    renderType: Text.QtRendering
                }

                MouseArea {
                    id: packageUrlMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (appBackend) appBackend.openPackageUrl()
                }
            }
        }
    }
}
