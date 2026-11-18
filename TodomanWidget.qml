import QtQuick
import QtQuick.Controls
import qs.Common
import qs.DCommon.Widgets

import qs.Modules.Plugins

PluginComponent {
    id: root
    pluginId: "dankTodoman"
    popoutWidth: 440
    popoutHeight: 560
    TodomanController {
        id: taskController
        pythonExecutable: root.pluginData.pythonExecutable || "python3"
        watchedLists: root.pluginData.listFilter || ""
        defaultList: root.pluginData.defaultList || ""
        sortField: root.pluginData.sortField || "due"
        showCompleted: root.pluginData.showCompleted === true
    }
    Timer { interval: (root.pluginData.refreshInterval || 5) * 60000; repeat: true; running: true; onTriggered: taskController.refresh() }
    horizontalBarPill: Component {
        StyledRect {
            implicitWidth: barRow.implicitWidth + Theme.spacingM * 2
            height: parent.widgetThickness; radius: Theme.cornerRadius; color: Theme.surfaceContainerHigh
            Row {
                id: barRow; anchors.centerIn: parent; spacing: Theme.spacingXS
                DIcon { name: "checklist"; size: root.iconSize; color: Theme.surfaceText; anchors.verticalCenter: parent.verticalCenter }
                StyledText { visible: taskController.openCount > 0 || taskController.unsupported.length > 0; text: taskController.countText; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeMedium; anchors.verticalCenter: parent.verticalCenter }
                StyledText { visible: root.pluginData.showNearestTask === true && !!taskController.nearest; text: taskController.nearest ? "· " + (taskController.nearest.summary.length > 22 ? taskController.nearest.summary.slice(0, 21) + "…" : taskController.nearest.summary) + " · " + taskController.countdown(taskController.nearest, false) : ""; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeMedium; anchors.verticalCenter: parent.verticalCenter }
            }
        }
    }
    verticalBarPill: Component {
        StyledRect {
            width: parent.widgetThickness; implicitHeight: barColumn.implicitHeight + Theme.spacingM * 2; radius: Theme.cornerRadius; color: Theme.surfaceContainerHigh
            Column {
                id: barColumn; anchors.centerIn: parent; spacing: 1
                DIcon { name: "checklist"; size: root.iconSize; color: Theme.surfaceText; anchors.horizontalCenter: parent.horizontalCenter }
                StyledText { visible: taskController.openCount > 0 || taskController.unsupported.length > 0; text: taskController.countText; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeSmall; anchors.horizontalCenter: parent.horizontalCenter }
                StyledText { visible: root.pluginData.showNearestTask === true && !!taskController.nearest; text: taskController.countdown(taskController.nearest, true); color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall; anchors.horizontalCenter: parent.horizontalCenter }
            }
        }
    }
    popoutContent: Component {
        PopoutComponent {
            id: popout
            property bool filtersOpen: false
            Item {
                width: parent.width
                height: Math.max(56, titleColumn.implicitHeight + 12)
                Column {
                    id: titleColumn
                    anchors.left: parent.left; anchors.right: actions.left; anchors.verticalCenter: parent.verticalCenter
                    StyledText { width: parent.width; text: taskController.editing ? (taskController.identity ? "Edit task" : "New task") : "Tasks"; font.pixelSize: Theme.fontSizeMedium + 3; font.weight: Font.DemiBold; color: Theme.surfaceText; elide: Text.ElideRight }
                    StyledText { width: parent.width; visible: !taskController.editing; text: taskController.countText + (taskController.openCount === 1 && !taskController.unsupported.length ? " open task" : " open tasks"); font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; elide: Text.ElideRight }
                }
                Row {
                    id: actions; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    DActionButton { visible: !taskController.editing; buttonSize: 40; iconName: "add"; tooltipText: "Add task"; focusPolicy: Qt.StrongFocus; enabled: !taskController.busy; onClicked: taskController.openNew() }
                    DActionButton { visible: !taskController.editing; buttonSize: 40; iconName: "search"; iconColor: popout.filtersOpen || taskController.search || taskController.viewList || taskController.category || taskController.priorityFilter !== "" || taskController.viewStatus !== "open" ? Theme.primary : Theme.surfaceVariantText; tooltipText: "Search and filters"; focusPolicy: Qt.StrongFocus; onClicked: popout.filtersOpen = !popout.filtersOpen }
                    DActionButton { visible: !taskController.editing; buttonSize: 40; iconName: "refresh"; tooltipText: "Refresh tasks"; focusPolicy: Qt.StrongFocus; onClicked: taskController.refresh() }
                }
            }
            Connections { target: popout.parentPopout; ignoreUnknownSignals: true; function onShouldBeVisibleChanged() { if (popout.parentPopout && popout.parentPopout.shouldBeVisible) taskController.refresh() } }
            TodomanAgenda { width: parent.width; height: Math.max(180, root.popoutHeight - 100); controller: taskController; filtersOpen: popout.filtersOpen; visible: !taskController.editing }
            TodomanTaskEditor { width: parent.width; height: Math.max(180, root.popoutHeight - 100); controller: taskController; visible: taskController.editing }
        }
    }
}