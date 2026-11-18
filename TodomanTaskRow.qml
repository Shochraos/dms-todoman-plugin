import QtQuick
import qs.Common
import qs.DCommon.Widgets

Item {
    id: row
    required property var task
    required property var controller
    implicitHeight: Math.max(52, textColumn.implicitHeight + 16)
    Rectangle {
        anchors.fill: parent; radius: 5
        color: row.activeFocus ? Theme.withAlpha(Theme.primary, 0.15) : rowHover.hovered ? Theme.surfaceContainerHigh : "transparent"
        border.width: row.activeFocus ? 2 : 0; border.color: Theme.primary
    }
    HoverHandler { id: rowHover }
    Rectangle { x: 8; anchors.verticalCenter: parent.verticalCenter; width: 4; height: Math.min(34, parent.height - 12); radius: 2; color: row.task.list_colour || Theme.primary }
    Column {
        id: textColumn
        x: 20; width: Math.max(0, parent.width - 68); anchors.verticalCenter: parent.verticalCenter
        StyledText { width: parent.width; text: row.task.summary || "(no summary)"; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.Wrap }
        StyledText { width: parent.width; text: [row.task.due ? Qt.formatDateTime(new Date(row.controller.dueTime(row.task.due)), row.task.due.kind === "date" ? "MMM d" : "MMM d, HH:mm") : "", row.task.list || "", row.task.recurring ? "Repeats" : "", row.task.priority ? "P" + row.task.priority : "", row.task.percent ? row.task.percent + "%" : ""].filter(function(s) { return s }).join(" · "); color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight }
    }
    MouseArea { anchors.left: parent.left; anchors.right: complete.left; anchors.top: parent.top; anchors.bottom: parent.bottom; onClicked: row.controller.openTask(row.task) }
    DActionButton {
        id: complete; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        buttonSize: 40; iconSize: 20; iconName: row.controller.isOpen(row.task) ? "radio_button_unchecked" : "check_circle"
        enabled: !row.controller.busy && row.controller.isOpen(row.task)
        tooltipText: "Complete " + row.task.summary; focusPolicy: Qt.StrongFocus
        onClicked: row.controller.action("complete", row.task)
    }
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: "Edit " + task.summary
    Keys.onReturnPressed: controller.openTask(task)
    Keys.onSpacePressed: controller.openTask(task)
}