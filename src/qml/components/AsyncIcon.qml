import QtQuick
import QtQuick.Controls

Item {
    id: root

    property string iconName: "application-x-executable"
    property int revision: 0
    property color placeholderColor: "#4b5160"
    property color accentColor: "#5294e2"
    property color spinnerColor: "#ffffff"
    property int iconSize: Math.min(width, height)
    property bool useCache: true
    property bool loading: false
    readonly property bool showSpinner: root.loading || (iconImage.source !== "" && iconImage.status === Image.Loading)
    readonly property string iconSource: root.loading
        ? ""
        : "image://desktopicons/" + encodeURIComponent(root.iconName || "application-x-executable") + "?rev=" + root.revision

    implicitWidth: 32
    implicitHeight: 32

    Rectangle {
        anchors.fill: parent
        color: root.placeholderColor
        visible: !root.showSpinner && iconImage.source !== "" && iconImage.status === Image.Error

        Rectangle {
            anchors.centerIn: parent
            width: Math.max(8, parent.width * 0.42)
            height: Math.max(8, parent.height * 0.42)
            color: root.accentColor
            radius: Math.max(4, width * 0.2)
        }
    }

    BusyIndicator {
        id: spinner
        anchors.centerIn: parent
        running: root.showSpinner
        visible: running
        width: Math.min(parent.width, 24)
        height: width

        contentItem: Item {
            implicitWidth: 20
            implicitHeight: 20

            RotationAnimator on rotation {
                from: 0
                to: 360
                duration: 900
                loops: Animation.Infinite
                running: spinner.running
            }

            Repeater {
                model: 8

                Rectangle {
                    required property int index

                    x: parent.width / 2 - width / 2 + Math.cos(index * Math.PI / 4) * (parent.width * 0.28)
                    y: parent.height / 2 - height / 2 + Math.sin(index * Math.PI / 4) * (parent.height * 0.28)
                    width: Math.max(2, parent.width * 0.1)
                    height: width
                    radius: width / 2
                    color: root.spinnerColor
                    opacity: 0.2 + (index / 10)
                }
            }
        }
    }

    Image {
        id: iconImage
        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize
        source: root.iconSource
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: root.useCache
        sourceSize.width: root.iconSize
        sourceSize.height: root.iconSize
        smooth: true
    }
}
