import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs
import QtQuick.Layouts
import Clerk

ApplicationWindow {
    id: window
    width: 1320
    height: 860
    minimumWidth: 980
    minimumHeight: 640
    visible: true
    title: "Clerk"

    Material.theme: Material.System
    Material.accent: Material.Teal
    Material.primary: Material.Teal

    readonly property real motion: Session.reduceMotion ? 0 : 1

    function files(n) { return n === 1 ? qsTr("1 file") : qsTr("%1 files").arg(n) }

    FolderDialog {
        id: folderDialog
        title: qsTr("Select a folder")
        onAccepted: Session.scan(selectedFolder)
    }

    StackLayout {
        anchors.fill: parent
        currentIndex: Session.state

        // Start
        Item {
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 64, 560)
                spacing: 18

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Clerk"
                    font.pixelSize: 44
                    font.weight: Font.DemiBold
                }
                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Find duplicate photos and videos in a folder.")
                    opacity: 0.7
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 230
                    radius: 18
                    color: drop.containsDrag ? Qt.rgba(Material.accentColor.r, Material.accentColor.g, Material.accentColor.b, 0.12) : "transparent"
                    border.width: 2
                    border.color: drop.containsDrag ? Material.accentColor : Qt.rgba(Material.foreground.r, Material.foreground.g, Material.foreground.b, 0.2)
                    Behavior on color { ColorAnimation { duration: 150 * window.motion } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 14
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: "⇩"
                            font.pixelSize: 44
                            opacity: 0.5
                        }
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: qsTr("Drop a folder here")
                        }
                        Button {
                            Layout.alignment: Qt.AlignHCenter
                            text: qsTr("Select a folder")
                            highlighted: true
                            onClicked: folderDialog.open()
                        }
                    }
                    DropArea {
                        id: drop
                        anchors.fill: parent
                        onDropped: event => {
                            if (event.hasUrls)
                                Session.scan(event.urls[0])
                        }
                    }
                }
                Label {
                    Layout.alignment: Qt.AlignHCenter
                    visible: text.length > 0
                    text: Session.error
                    color: Material.color(Material.Red)
                }
            }
        }

        ScanView {}

        ResultsView {}

        // Done
        Item {
            id: doneView
            readonly property var report: Session.report

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 64, 560)
                spacing: 16

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: "✓"
                    font.pixelSize: 56
                    color: Material.accentColor
                }
                Label {
                    Layout.alignment: Qt.AlignHCenter
                    font.pixelSize: 20
                    text: doneView.report.restored >= 0
                          ? qsTr("Moved %1 back from the Trash.").arg(window.files(doneView.report.restored))
                          : qsTr("Moved %1 to the Trash. This frees %2.")
                                .arg(window.files(doneView.report.moved))
                                .arg(Qt.locale().formattedDataSize(doneView.report.bytes ?? 0))
                }
                Repeater {
                    model: doneView.report.failed ?? []
                    delegate: Label {
                        required property var modelData
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Material.color(Material.Red)
                        text: qsTr("%1: %2").arg(modelData.name).arg(modelData.reason)
                    }
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 12
                    Button {
                        visible: doneView.report.restored < 0 && doneView.report.moved > 0
                        text: qsTr("Undo")
                        onClicked: Session.undo()
                    }
                    Button {
                        text: qsTr("Examine the folder again")
                        highlighted: true
                        onClicked: Session.scan(Session.folder)
                    }
                    Button {
                        text: qsTr("Select another folder")
                        flat: true
                        onClicked: Session.reset()
                    }
                }
            }
        }
    }
}
