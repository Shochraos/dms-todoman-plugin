import QtQuick
import qs.Common
import qs.DCommon.Common
import qs.DCommon.Widgets

Item {
    id: row

    required property var task
    required property var controller
    required property Item ownerAgenda
    property real textInset: Theme.spacingS
    property bool highlighted: false

    readonly property string summary: task.summary || "(no summary)"
    readonly property bool open: controller.isOpen(task)
    readonly property bool cancelled: task.status === "CANCELLED"
    readonly property string statusLabel: cancelled ? "Cancelled" : !open ? "Completed" : task.status === "IN-PROCESS" ? "In progress" : ""
    readonly property string dueLabel: task.due ? Qt.formatDateTime(new Date(controller.dueTime(task.due)), task.due.kind === "date" ? "MMM d" : "MMM d, HH:mm") : ""
    readonly property string metadata: [statusLabel, dueLabel, highlighted ? "Next" : "", task.list, task.recurring ? "Repeats" : "", task.priority ? "P" + task.priority : "", open && task.percent ? task.percent + "%" : ""].filter(value => !!value).join(" · ")
    readonly property bool controlPressed: edit.pressed || complete.pressed

    onControlPressedChanged: controller.setRowPressed(row, controlPressed)
    Component.onDestruction: controller?.setRowPressed(row, false)

    implicitHeight: Math.max(52, textColumn.implicitHeight + Theme.spacingS * 2)
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        visible: row.highlighted
        color: Theme.withAlpha(Theme.primary, 0.18)
        radius: Theme.cornerRadiusS
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, 0.64)
    }

    DListItem {
        id: edit

        anchors.left: parent.left
        anchors.right: rowAction.left
        anchors.rightMargin: Theme.spacingXS
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        surfaceColor: "transparent"
        border.width: 0
        topLeftRadius: Style.cornerRadiusS
        topRightRadius: Style.cornerRadiusS
        bottomLeftRadius: Style.cornerRadiusS
        bottomRightRadius: Style.cornerRadiusS
        enabled: row.controller.rowActionsAvailable
        Accessible.role: Accessible.Button
        Accessible.name: "Edit " + row.summary
        Accessible.description: row.metadata
        tooltipText: title.truncated || detail.truncated ? row.summary + (row.metadata ? "\n" + row.metadata : "") : null
        onClicked: row.controller.requestRowAction("detail", row.task, row.ownerAgenda)

        Rectangle {
            id: marker
            x: row.textInset
            anchors.verticalCenter: parent.verticalCenter
            width: 4
            height: Math.min(34, parent.height - Theme.spacingS * 2)
            radius: width / 2
            color: !row.open ? Theme.surfaceVariantText : row.controller.overdue(row.task) ? Theme.error : row.task.list_colour || Theme.primary
        }

        Column {
            id: textColumn

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: marker.x + marker.width + Theme.spacingS
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            StyledText {
                id: title

                width: parent.width
                text: row.summary
                textFormat: Text.PlainText
                color: edit.visualFocus ? edit.contentColor : Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                elide: Text.ElideRight
                maximumLineCount: 1
                wrapMode: Text.NoWrap
                Accessible.ignored: true
            }

            StyledText {
                id: detail

                width: parent.width
                visible: row.metadata !== ""
                text: row.metadata
                textFormat: Text.PlainText
                color: edit.visualFocus ? edit.supportingContentColor : Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
                Accessible.ignored: true
            }
        }
    }

    Item {
        id: rowAction

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 40
        height: 40

        DActionButton {
            id: complete
            visible: row.open
            buttonSize: 40
            iconName: "radio_button_unchecked"
            enabled: row.controller.rowActionsAvailable
            tooltipText: "Complete " + row.summary
            onClicked: row.controller.requestRowAction("complete", row.task, row.ownerAgenda)
        }

        DIcon {
            visible: !row.open
            anchors.centerIn: parent
            name: row.cancelled ? "cancel" : "check_circle"
            size: Style.iconSizeMedium
            color: Theme.surfaceVariantText
            Accessible.ignored: true
        }
    }
}
