import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "components"
import "layouts"
import "style" as Style

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
        resultsPanel.focusSearch()
    })

    Style.Palette {
        id: palette
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: palette.backgroundElevated }
            GradientStop { position: 0.55; color: "#2f343f" }
            GradientStop { position: 1.0; color: palette.backgroundCanvas }
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

        ResultsPanel {
            id: resultsPanel
            theme: palette
            backend: appBackend
        }

        AppSurface {
            SplitView.fillWidth: true
            SplitView.minimumWidth: 460
            backgroundColor: palette.surfaceRight
            outlineColor: palette.borderStrong

            Item {
                anchors.fill: parent
                anchors.margins: 24

                DetailsPane {
                    anchors.fill: parent
                    visible: window.hasSelection
                    theme: palette
                    backend: appBackend
                    iconPicker: iconPicker
                }

                EmptyState {
                    visible: !window.hasSelection
                    theme: palette
                }

                IconPickerDialog {
                    id: iconPicker
                    theme: palette
                    backend: appBackend
                    hostWindow: window
                }
            }
        }
    }
}
