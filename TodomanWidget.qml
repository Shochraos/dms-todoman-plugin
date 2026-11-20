import QtQuick
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
        pythonExecutable: root.pluginData.pythonExecutable || ""
        watchedLists: root.pluginData.listFilter || ""
        defaultList: root.pluginData.defaultList || ""
        sortField: root.pluginData.sortField || "due"
        futureTasks: root.pluginData.futureTasks || "config"
        showCompleted: root.pluginData.showCompleted === true
    }
    Timer { interval: Math.max(1, Number(root.pluginData.refreshInterval) || 5) * 60000; repeat: true; running: true; onTriggered: taskController.refresh() }
    function nearestSummary(task) {
        var text = ((task && task.summary) || "").trim() || "(no summary)"
        return text.length > 22 ? text.slice(0, 21) + "…" : text
    }
    horizontalBarPill: Component {
        StyledRect {
            implicitWidth: barRow.implicitWidth + Theme.spacingM * 2
            height: parent.widgetThickness; radius: Theme.cornerRadius; color: Theme.surfaceContainerHigh
            Row {
                id: barRow; anchors.centerIn: parent; spacing: Theme.spacingXS
                DIcon { name: "checklist"; size: root.iconSize; color: taskController.openCount > 0 || taskController.unsupported.length > 0 ? Theme.surfaceText : Theme.surfaceVariantText; anchors.verticalCenter: parent.verticalCenter }
                StyledText { visible: taskController.openCount > 0 || taskController.unsupported.length > 0; text: taskController.countText; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeMedium; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
                StyledText {
                    readonly property bool shown: root.pluginData.showNearestTask === true && !!taskController.nearest
                    visible: shown
                    text: shown ? "· " + root.nearestSummary(taskController.nearest) : ""
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }
                StyledText {
                    readonly property bool shown: root.pluginData.showNearestTask === true && !!taskController.nearest
                    visible: shown
                    text: shown ? "· " + taskController.countdown(taskController.nearest, false) : ""
                    color: shown && taskController.overdue(taskController.nearest) ? Theme.error : Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
    verticalBarPill: Component {
        StyledRect {
            width: parent.widgetThickness; implicitHeight: barColumn.implicitHeight + Theme.spacingM * 2; radius: Theme.cornerRadius; color: Theme.surfaceContainerHigh
            Column {
                id: barColumn; anchors.centerIn: parent; spacing: 1
                DIcon { name: "checklist"; size: root.iconSize; color: taskController.openCount > 0 || taskController.unsupported.length > 0 ? Theme.surfaceText : Theme.surfaceVariantText; anchors.horizontalCenter: parent.horizontalCenter }
                StyledText { visible: taskController.openCount > 0 || taskController.unsupported.length > 0; text: taskController.countText; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeSmall; anchors.horizontalCenter: parent.horizontalCenter }
                StyledText {
                    readonly property bool shown: root.pluginData.showNearestTask === true && !!taskController.nearest
                    visible: shown
                    text: shown ? taskController.countdown(taskController.nearest, true) : ""
                    color: shown && taskController.overdue(taskController.nearest) ? Theme.error : Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }
    popoutContent: Component {
        PopoutComponent {
            id: popout

            readonly property real bodyHeight: Math.max(180, root.popoutHeight - headerHeight - detailsHeight - PopoutMetrics.contentPadding * 2)

            headerText: taskController.editing ? (taskController.identity ? "Edit task" : "New task") : "Tasks"
            detailsText: taskController.editing ? "" : taskController.countText + (taskController.openCount === 1 && !taskController.unsupported.length ? " open task" : " open tasks")
            headerActions: taskController.editing ? null : agendaActions

            Component {
                id: agendaActions

                Row {
                    spacing: Theme.spacingXS

                    DActionButton {
                        buttonSize: 40
                        iconName: "add"
                        tooltipText: "Add task"
                        enabled: !taskController.busy && !taskController.unknownOutcome
                        onClicked: taskController.openNew()
                    }

                    DActionButton {
                        id: searchAction
                        buttonSize: 40
                        iconName: "search"
                        iconColor: agenda.searchVisible ? Theme.primary : Theme.surfaceVariantText
                        tooltipText: agenda.searchVisible ? "Close search" : "Search tasks"
                        onClicked: agenda.searchVisible ? agenda.closeSearch() : agenda.openSearch()

                        Connections {
                            target: agenda
                            function onSearchClosed() { searchAction.forceActiveFocus() }
                        }
                    }

                    DActionButton {
                        id: filterAction
                        buttonSize: 40
                        iconName: "filter_list"
                        iconColor: agenda.filtersOpen || agenda.hasFilters ? Theme.primary : Theme.surfaceVariantText
                        tooltipText: agenda.filtersOpen ? "Hide filters" : "Show filters"
                        Accessible.description: agenda.hasFilters ? "Filters applied" : ""
                        onClicked: agenda.filtersOpen = !agenda.filtersOpen

                        Connections {
                            target: agenda
                            function onFilterFocusRequested() { filterAction.forceActiveFocus() }
                        }
                    }

                    DActionButton {
                        buttonSize: 40
                        iconName: "refresh"
                        tooltipText: "Refresh tasks"
                        enabled: !taskController.busy
                        onClicked: taskController.refresh(true)
                    }
                }
            }

            Keys.onPressed: event => {
                if (taskController.editing)
                    return;
                if (event.key === Qt.Key_F && event.modifiers === Qt.ControlModifier) {
                    agenda.openSearch();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape && agenda.filtersOpen) {
                    agenda.filtersOpen = false;
                    agenda.filterFocusRequested();
                    event.accepted = true;
                }
            }

            Connections {
                target: popout.parentPopout
                ignoreUnknownSignals: true

                function onShouldBeVisibleChanged() {
                    if (popout.parentPopout && popout.parentPopout.shouldBeVisible) {
                        taskController.refresh();
                    } else {
                        agenda.filtersOpen = false;
                        agenda.searchOpen = false;
                    }
                }
            }

            TodomanAgenda {
                id: agenda
                width: popout.width
                height: popout.bodyHeight
                controller: taskController
                visible: !taskController.editing
            }

            TodomanTaskEditor {
                width: popout.width
                height: popout.bodyHeight
                controller: taskController
                visible: taskController.editing
            }
        }
    }
}