import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Clerk

Item {
    id: root

    readonly property real motion: Session.reduceMotion ? 0 : 1
    readonly property var steps: [qsTr("Examine files"), qsTr("Compare files"), qsTr("Make groups")]
    readonly property color faint: Qt.rgba(Material.foreground.r, Material.foreground.g, Material.foreground.b, 0.2)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 32
        spacing: 18

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10

            Repeater {
                model: root.steps
                delegate: RowLayout {
                    id: step
                    required property int index
                    required property string modelData
                    readonly property bool past: index < Session.stage
                    readonly property bool current: index === Session.stage
                    spacing: 10

                    Rectangle {
                        width: 28
                        height: 28
                        radius: 14
                        color: step.past ? Material.accentColor : "transparent"
                        border.width: 2
                        border.color: step.past || step.current ? Material.accentColor : root.faint
                        Label {
                            anchors.centerIn: parent
                            text: step.past ? "✓" : step.index + 1
                            color: step.past ? "white" : Material.foreground
                        }
                        SequentialAnimation on scale {
                            running: step.current && root.motion > 0
                            loops: Animation.Infinite
                            NumberAnimation {
                                to: 1.12; duration: 500; easing.type: Easing.InOutSine
                            }
                            NumberAnimation {
                                to: 1.0; duration: 500; easing.type: Easing.InOutSine
                            }
                        }
                    }
                    Label {
                        text: step.modelData
                        font.weight: step.current ? Font.DemiBold : Font.Normal
                        opacity: step.past || step.current ? 1 : 0.5
                    }
                    Rectangle {
                        visible: step.index < root.steps.length - 1
                        width: 48
                        height: 2
                        color: step.past ? Material.accentColor : root.faint
                        Behavior on color {
                            ColorAnimation {
                                duration: 300 * root.motion
                            }
                        }
                    }
                }
            }
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            font.pixelSize: 20
            text: Session.stage === 0 ? qsTr("Examine files: %1 of %2.").arg(Session.done).arg(Session.files.length)
                : Session.stage === 1 ? qsTr("Compare all files with each other.")
                    : qsTr("Make groups of duplicates.")
        }

        ProgressBar {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            Layout.maximumWidth: 640
            value: Session.files.length > 0 ? Session.done / Session.files.length : 0
            indeterminate: Session.stage > 0
        }

        GridView {
            id: grid
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.max(cellWidth, Math.floor(parent.width / cellWidth) * cellWidth)
            Layout.fillHeight: true
            clip: true
            cellWidth: 116
            cellHeight: 116
            model: Session.files
            ScrollBar.vertical: ScrollBar {
            }

            delegate: Item {
                id: cell
                required property int index
                required property string modelData
                readonly property int fileState: Session.fileState[index] ?? 0 // 0 waiting, 1 in progress, 2 done
                width: grid.cellWidth
                height: grid.cellHeight

                Accessible.role: Accessible.Graphic
                Accessible.name: modelData.split("/").pop()

                Rectangle {
                    anchors.fill: thumb
                    anchors.margins: -5
                    radius: 12
                    color: "transparent"
                    border.width: 3
                    border.color: Material.accentColor
                    visible: cell.fileState === 1
                    SequentialAnimation on opacity {
                        running: cell.fileState === 1 && root.motion > 0
                        loops: Animation.Infinite
                        NumberAnimation {
                            to: 0.25; duration: 550; easing.type: Easing.InOutSine
                        }
                        NumberAnimation {
                            to: 1.0; duration: 550; easing.type: Easing.InOutSine
                        }
                    }
                }

                Image {
                    id: thumb
                    anchors.centerIn: parent
                    width: 96
                    height: 96
                    source: "image://thumb/" + encodeURIComponent(cell.modelData)
                    sourceSize: Qt.size(192, 192)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    opacity: cell.fileState === 2 ? 1 : cell.fileState === 1 ? 0.9 : 0.25
                    scale: cell.fileState === 1 ? 1.06 : 1
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 350 * root.motion
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: 250 * root.motion; easing.type: Easing.OutBack
                        }
                    }
                }

                Rectangle {
                    anchors.right: thumb.right
                    anchors.bottom: thumb.bottom
                    anchors.margins: -6
                    width: 22
                    height: 22
                    radius: 11
                    color: Material.accentColor
                    opacity: cell.fileState === 2 ? 1 : 0
                    scale: cell.fileState === 2 ? 1 : 0.4
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 250 * root.motion
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: 250 * root.motion; easing.type: Easing.OutBack
                        }
                    }
                    Label {
                        anchors.centerIn: parent
                        text: "✓"
                        color: "white"
                        font.pixelSize: 12
                    }
                }

                Label {
                    visible: /\.(mp4|mov|m4v)$/i.test(cell.modelData)
                    anchors.left: thumb.left
                    anchors.bottom: thumb.bottom
                    anchors.margins: 4
                    text: "▶"
                    color: "white"
                    style: Text.Outline
                    styleColor: "#80000000"
                }
            }
        }

        Button {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Stop")
            flat: true
            onClicked: Session.cancel()
        }
    }
}
