import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Clerk

Item {
    id: root

    readonly property real motion: Session.reduceMotion ? 0 : 1
    readonly property int level: tabs.currentIndex
    readonly property var levelNames: [qsTr("Exact"), qsTr("Similar"), qsTr("Related")]
    readonly property var levelHints: [
        qsTr("The same picture. Only the file is different."),
        qsTr("The differences are there, but they are minor. "),
        qsTr("Same place, light and colours. You can see the difference easily.")
    ]
    property int selectedGroup: -1
    property int selectedId: -1

    function marked(id) { return Session.trash.indexOf(id) >= 0 }
    function size(bytes) { return Qt.locale().formattedDataSize(bytes) }
    function files(n) { return n === 1 ? qsTr("1 file") : qsTr("%1 files").arg(n) }

    onLevelChanged: selectedId = -1

    RowLayout {
        anchors.fill: parent
        spacing: 0

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Pane {
                Layout.fillWidth: true
                padding: 12
                RowLayout {
                    anchors.fill: parent
                    spacing: 12
                    TabBar {
                        id: tabs
                        Repeater {
                            model: 3
                            TabButton {
                                required property int index
                                width: implicitWidth
                                text: root.levelNames[index] + "  " + (Session.groups[index] ?? []).length
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Button {
                        visible: root.level < 2 && (Session.groups[root.level] ?? []).length > 0
                        text: qsTr("Keep best quality in all groups")
                        onClicked: Session.keepBestQualityAll(root.level)
                        ToolTip.visible: hovered
                        ToolTip.delay: 500
                        ToolTip.text: qsTr("Keeps the best file of each group. It marks the other files only if the match is sure (90% or more).")
                    }
                    Button {
                        text: qsTr("Select another folder")
                        flat: true
                        onClicked: Session.reset()
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                leftPadding: 24
                topPadding: 12
                text: root.levelHints[root.level]
                opacity: 0.7
            }
            Label {
                Layout.fillWidth: true
                leftPadding: 24
                visible: Session.skipped.length > 0
                color: Material.color(Material.Orange)
                text: qsTr("Did not examine %1. Point to this text to see why.").arg(root.files(Session.skipped.length))
                HoverHandler { id: skippedHover }
                ToolTip.visible: skippedHover.hovered
                ToolTip.text: Session.skipped.map(s => s.name + ": " + s.reason).join("\n")
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 16
                topMargin: 16
                bottomMargin: 16
                leftMargin: 24
                rightMargin: 24
                model: Session.groups[root.level] ?? []
                delegate: GroupCard {}
                ScrollBar.vertical: ScrollBar {}
                populate: Transition {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 250 * root.motion }
                    NumberAnimation { property: "y"; from: 24; duration: 250 * root.motion; easing.type: Easing.OutCubic }
                }

                Label {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: qsTr("No groups at this level.")
                    opacity: 0.6
                    font.pixelSize: 18
                }
            }

            Pane {
                Layout.fillWidth: true
                padding: 14
                Material.elevation: 6
                RowLayout {
                    anchors.fill: parent
                    Label {
                        text: Session.trash.length === 0
                              ? qsTr("Keeps all files. Mark the files to delete.")
                              : qsTr("Delete %1. This frees %2.").arg(root.files(Session.trash.length)).arg(root.size(Session.trashBytes))
                    }
                    Item { Layout.fillWidth: true }
                    Button {
                        text: qsTr("Move to Trash...")
                        enabled: Session.trash.length > 0
                        highlighted: true
                        Material.accent: Material.Red
                        onClicked: confirm.open()
                    }
                }
            }
        }

        Inspector {
            Layout.fillHeight: true
            Layout.preferredWidth: root.selectedId >= 0 ? 400 : 0
            Behavior on Layout.preferredWidth { NumberAnimation { duration: 220 * root.motion; easing.type: Easing.OutCubic } }
            visible: Layout.preferredWidth > 0
            level: root.level
            group: root.selectedGroup
            mediaId: root.selectedId
            onClosed: root.selectedId = -1
        }
    }

    Dialog {
        id: confirm
        anchors.centerIn: Overlay.overlay
        modal: true
        title: qsTr("Delete %1?").arg(root.files(Session.trash.length))
        standardButtons: Dialog.Ok | Dialog.Cancel
        Component.onCompleted: standardButton(Dialog.Ok).text = qsTr("Move to Trash")
        onAccepted: Session.moveToTrash()
        Label {
            text: qsTr("Move the files to the Trash. You can undo this.")
        }
    }

    component GroupCard: Pane {
        id: card
        required property int index
        required property var modelData
        readonly property bool allMarked: modelData.members.every(id => root.marked(id))
        width: ListView.view.width - 48
        padding: 16
        Material.elevation: 2
        Material.roundedScale: Material.MediumScale

        ColumnLayout {
            width: parent.width
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: qsTr("Group %1").arg(card.index + 1)
                    font.weight: Font.DemiBold
                    font.pixelSize: 16
                }
                Label {
                    text: root.files(card.modelData.members.length)
                    opacity: 0.6
                }
                Item { Layout.fillWidth: true }
                Button {
                    visible: root.level < 2
                    flat: true
                    text: qsTr("Keep best quality")
                    onClicked: Session.keepBestQuality(root.level, card.index)
                }
            }
            Label {
                Layout.fillWidth: true
                visible: card.allMarked
                wrapMode: Text.Wrap
                color: Material.color(Material.Orange)
                text: qsTr("You marked all files in this group. Keep one file or continue.")
            }
            Flow {
                Layout.fillWidth: true
                spacing: 14
                Repeater {
                    model: card.modelData.members
                    delegate: Tile {
                        groupIndex: card.index
                        reference: card.modelData.reference
                        link: card.modelData.links[String(modelData)]
                    }
                }
            }
        }
    }

    component Tile: ColumnLayout {
        id: tile
        required property int modelData // media id
        property int groupIndex
        property int reference
        property var link // {confidence, kind}
        readonly property var info: Session.items[modelData]
        readonly property bool deleting: root.marked(modelData)
        readonly property bool selected: root.selectedId === modelData && root.selectedGroup === groupIndex
        width: 190
        spacing: 6

        Rectangle {
            Layout.preferredWidth: 190
            Layout.preferredHeight: 190
            radius: 12
            color: Qt.rgba(Material.foreground.r, Material.foreground.g, Material.foreground.b, 0.05)
            border.width: tile.selected ? 3 : tile.deleting ? 2 : 0
            border.color: tile.selected ? Material.accentColor : Material.color(Material.Red)
            scale: hover.hovered ? 1.03 : 1
            Behavior on scale { NumberAnimation { duration: 150 * root.motion } }

            Image {
                anchors.fill: parent
                anchors.margins: 5
                source: "image://thumb/" + encodeURIComponent(tile.info.path)
                sourceSize: Qt.size(380, 380)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                opacity: tile.deleting ? 0.35 : 1
                Behavior on opacity { NumberAnimation { duration: 200 * root.motion } }
            }
            Label {
                anchors.centerIn: parent
                visible: tile.deleting
                text: qsTr("Delete")
                font.weight: Font.Bold
                color: Material.color(Material.Red)
            }
            Rectangle {
                visible: tile.modelData === tile.reference
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 8
                width: bestLabel.implicitWidth + 14
                height: 22
                radius: 11
                color: Material.accentColor
                Label {
                    id: bestLabel
                    anchors.centerIn: parent
                    text: qsTr("★ Best")
                    color: "white"
                    font.pixelSize: 12
                }
            }
            Rectangle {
                visible: tile.link !== undefined
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                width: confidenceLabel.implicitWidth + 14
                height: 22
                radius: 11
                color: "#B0000000"
                Label {
                    id: confidenceLabel
                    anchors.centerIn: parent
                    text: tile.link ? Math.round(tile.link.confidence * 100) + " %" : ""
                    color: "white"
                    font.pixelSize: 12
                }
            }
            Label {
                visible: tile.info.video
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 8
                text: "▶ " + Math.round(tile.info.seconds) + " s"
                color: "white"
                style: Text.Outline
                styleColor: "#80000000"
            }
            HoverHandler {
                id: hover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                onTapped: {
                    root.selectedGroup = tile.groupIndex
                    root.selectedId = tile.modelData
                }
            }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Show details of %1").arg(tile.info.name)
        }

        Label {
            Layout.preferredWidth: 190
            text: tile.info.name
            elide: Text.ElideMiddle
            font.pixelSize: 12
            opacity: 0.8
        }
        RowLayout {
            Layout.preferredWidth: 190
            Label {
                text: tile.link ? tile.link.kind : qsTr("Best quality")
                font.pixelSize: 12
                opacity: 0.6
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Button {
                flat: true
                implicitHeight: 34
                text: tile.deleting ? qsTr("Keep") : qsTr("Delete")
                Material.foreground: tile.deleting ? Material.accentColor : Material.color(Material.Red)
                onClicked: Session.toggle(tile.modelData)
            }
        }
    }
}
