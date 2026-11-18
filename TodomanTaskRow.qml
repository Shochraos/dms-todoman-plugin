import QtQuick
import qs.Common
import qs.DCommon.Common
import qs.DCommon.Widgets

Item {
    id: row

    required property var task
    required property var controller
    property real textInset: Theme.spacingS

    readonly property string summary: task.summary || "(no summary)"
    readonly property bool open: controller.isOpen(task)
    readonly property bool cancelled: task.status === "CANCELLED"
    readonly property string statusLabel: cancelled ? "Cancelled" : !open ? "Completed" : task.status === "IN-PROCESS" ? "In progress" : ""
    readonly property string dueLabel: task.due ? Qt.formatDateTime(new Date(controller.dueTime(task.due)), task.due.kind === "date" ? "MMM d" : "MMM d, HH:mm") : ""
    readonly property string metadata: [statusLabel, dueLabel, task.list, task.recurring ? "Repeats" : "", task.priority ? "P" + task.priority : "", open && task.percent ? task.percent + "%" : ""].filter(value => !!value).join(" · ")

    implicitHeight: Math.max(52, textColumn.implicitHeight + Theme.spacingS * 2)
    height: implicitHeight

    DListItem {
        id: edit

        anchors.left: parent.left
        anchors.right: rowAction.left
        anchors.rightMargin: Theme.spacingXS
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        surfaceColor: "transparent"
        border.width: 0
        topLeftRadius: Style.cornerRadiusM
        topRightRadius: Style.cornerRadiusM
        bottomLeftRadius: Style.cornerRadiusM
        bottomRightRadius: Style.cornerRadiusM
        enabled: !row.controller.busy && !row.controller.unknownOutcome
        Accessible.role: Accessible.Button
        Accessible.name: "Edit " + row.summary
        Accessible.description: row.metadata
        tooltipText: title.truncated || detail.truncated ? row.summary + (row.metadata ? "\n" + row.metadata : "") : null
        onClicked: row.controller.openTask(row.task)

        Rectangle {
            x: Math.max(0, row.textInset - Theme.spacingS)
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: Math.min(32, textColumn.implicitHeight)
            radius: width / 2
            color: row.task.list_colour || Theme.primary
        }

        Column {
            id: textColumn

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: row.textInset
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXXS

            StyledText {
                id: title

                width: parent.width
                text: row.summary
                textFormat: Text.PlainText
                color: edit.visualFocus ? edit.contentColor : Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
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
            visible: row.open
            buttonSize: 40
            iconName: "radio_button_unchecked"
            enabled: !row.controller.busy && !row.controller.unknownOutcome
            tooltipText: "Complete " + row.summary
            onClicked: row.controller.action("complete", row.task)
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
