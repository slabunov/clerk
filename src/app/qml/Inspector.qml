import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Clerk

Pane {
    id: panel

    property int level
    property int group: -1
    property int mediaId: -1
    signal closed()

    readonly property var d: mediaId >= 0 && group >= 0 ? Session.details(level, group, mediaId) : null
    readonly property bool deleting: Session.trash.indexOf(mediaId) >= 0
    readonly property color faint: Qt.rgba(Material.foreground.r, Material.foreground.g, Material.foreground.b, 0.12)

    padding: 0
    Material.elevation: 8

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth

        ColumnLayout {
            x: 20
            width: 360
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 12
                Label {
                    text: qsTr("Details")
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }
                Item { Layout.fillWidth: true }
                ToolButton {
                    text: "✕"
                    onClicked: panel.closed()
                    Accessible.name: qsTr("Close details")
                }
            }

            Image {
                Layout.fillWidth: true
                Layout.preferredHeight: 280
                source: panel.d ? "image://thumb/" + encodeURIComponent(panel.d.path) : ""
                sourceSize: Qt.size(720, 720)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }
            Label {
                Layout.fillWidth: true
                text: panel.d ? panel.d.name : ""
                wrapMode: Text.WrapAnywhere
                font.weight: Font.DemiBold
            }
            Label {
                Layout.fillWidth: true
                opacity: 0.7
                text: !panel.d ? "" : panel.d.width + " × " + panel.d.height
                      + " · " + Qt.locale().formattedDataSize(panel.d.bytes)
                      + (panel.d.video ? " · " + Math.round(panel.d.seconds) + " s" : "")
            }
            RowLayout {
                spacing: 8
                Button {
                    text: qsTr("Open")
                    onClicked: Qt.openUrlExternally(panel.d.url)
                }
                Button {
                    text: panel.deleting ? qsTr("Keep") : qsTr("Delete")
                    Material.foreground: panel.deleting ? Material.accentColor : Material.color(Material.Red)
                    onClicked: Session.toggle(panel.mediaId)
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: panel.faint }

            Label {
                text: qsTr("Match")
                font.pixelSize: 16
                font.weight: Font.DemiBold
            }
            Label {
                Layout.fillWidth: true
                visible: panel.d !== null && panel.d.reference
                wrapMode: Text.Wrap
                text: qsTr("This file has the best quality in the group. Other files will be compared with it.")
            }
            ColumnLayout {
                Layout.fillWidth: true
                visible: panel.d !== null && panel.d.confidence !== undefined
                spacing: 10

                RowLayout {
                    spacing: 12
                    Label {
                        text: panel.d && panel.d.confidence !== undefined ? Math.round(panel.d.confidence * 100) + " %" : ""
                        font.pixelSize: 34
                        font.weight: Font.DemiBold
                        color: Material.accentColor
                    }
                    ColumnLayout {
                        spacing: 2
                        Label {
                            text: panel.d ? qsTr("confidence") : ""
                            opacity: 0.7
                        }
                        Label {
                            text: panel.d && panel.d.kind ? panel.d.kind : ""
                            font.weight: Font.DemiBold
                        }
                    }
                }
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WrapAnywhere
                    opacity: 0.7
                    text: panel.d && panel.d.comparedWith ? qsTr("Compared with %1").arg(panel.d.comparedWith) : ""
                }

                Repeater {
                    model: panel.d && panel.d.criteria ? panel.d.criteria : []
                    delegate: ColumnLayout {
                        id: row
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: row.modelData.label }
                            Item { Layout.fillWidth: true }
                            Label {
                                text: row.modelData.value
                                opacity: 0.7
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                            height: 6
                            Rectangle {
                                anchors.fill: parent
                                radius: 3
                                color: panel.faint
                            }
                            Rectangle {
                                readonly property real half: parent.width / 2
                                height: parent.height
                                radius: 3
                                width: Math.abs(row.modelData.bar) * half
                                x: row.modelData.bar >= 0 ? half : half - width
                                color: row.modelData.bar >= 0 ? Material.accentColor : Material.color(Material.Red)
                            }
                            Rectangle {
                                x: parent.width / 2
                                width: 1
                                height: parent.height + 4
                                y: -2
                                color: Material.foreground
                                opacity: 0.4
                            }
                        }
                    }
                }
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: 12
                    opacity: 0.6
                    text: qsTr("A bar to the right makes the match more sure. A bar to the left makes it less sure.")
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: panel.faint }

            Label {
                text: qsTr("Quality")
                font.pixelSize: 16
                font.weight: Font.DemiBold
            }
            Repeater {
                model: panel.d ? panel.d.quality : []
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Label { text: modelData.label }
                    Item { Layout.fillWidth: true }
                    Label {
                        text: modelData.value
                        opacity: 0.7
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 20
                Label {
                    text: qsTr("Quality score")
                    font.weight: Font.DemiBold
                }
                Item { Layout.fillWidth: true }
                Label {
                    text: panel.d ? panel.d.score.toFixed(1) : ""
                    font.weight: Font.DemiBold
                }
            }
        }
    }
}
