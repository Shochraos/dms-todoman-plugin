import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root
    pluginId: "dankTodoman"
    popoutWidth: 440
    popoutHeight: 560

    readonly property bool showBarCount: taskController.openCount > 0 || taskController.unsupported.length > 0
    readonly property var previewTask: taskController.nearest
    readonly property string previewTitle: (previewTask?.summary || "").trim() || "(no summary)"
    readonly property bool previewOverdue: !!previewTask && taskController.overdue(previewTask)
    readonly property bool showBarCountdown: root.pluginData.showNearestTask === true && !!previewTask
    readonly property color barIconColor: showBarCount ? Theme.primary : Theme.widgetIconColor
    readonly property color barCountdownColor: previewOverdue ? Theme.error : Theme.primary

    function previewAnchor() {
        const anchor = root.surfaceContext?.popupAnchor(root, root.section, null, undefined, false)
        if (anchor)
            return anchor

        const position = root.barConfig?.position ?? (root.isVertical ? 2 : 0)
        const point = root.mapToItem(null, 0, 0)
        const extent = root.isVertical ? root.height : root.width
        return {
            position,
            screen: root.parentScreen,
            trigger: SettingsData.getPopupTriggerPosition(point, root.parentScreen, root.barThickness, extent, root.barSpacing, position, root.barConfig)
        }
    }

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

    HoverHandler {
        id: pillHover
        enabled: root.surfaceLive && !root.interactionActive && !!root.parentScreen && !!root.previewTask
    }

    Loader {
        active: pillHover.enabled && pillHover.hovered
        sourceComponent: PanelWindow {
            id: preview

            property var placement: root.previewAnchor()
            readonly property int edge: placement.position
            readonly property var trigger: placement.trigger
            readonly property var due: root.previewTask?.due
            readonly property string location: (root.previewTask?.location || "").trim()

            screen: placement.screen
            color: "transparent"
            implicitWidth: Math.min(Theme.fontSizeSmall * 24 + Theme.spacingM * 2, Math.max(1, (screen?.width ?? Screen.width) - Theme.spacingS * 2))
            implicitHeight: details.implicitHeight + Theme.spacingS * 2
            WlrLayershell.namespace: "dms:plugins:danktodoman-tooltip"
            WlrLayershell.layer: WlrLayershell.Overlay
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}

            anchors { left: true; top: true }
            margins {
                left: preview.boundedMargin(preview.trigger.x - (preview.edge === 3 ? preview.implicitWidth : 0), preview.screen?.width ?? Screen.width, preview.implicitWidth)
                top: {
                    let y = preview.trigger.y
                    if (preview.edge === 1)
                        y -= preview.implicitHeight
                    else if (preview.edge === 2 || preview.edge === 3)
                        y += (preview.trigger.width - preview.implicitHeight) / 2
                    return preview.boundedMargin(y, preview.screen?.height ?? Screen.height, preview.implicitHeight)
                }
            }

            function boundedMargin(offset, available, size) {
                return Math.round(Math.max(Theme.spacingS, Math.min(offset, available - size - Theme.spacingS)))
            }

            Timer {
                interval: 100
                running: preview.visible
                repeat: true
                onTriggered: {
                    const next = root.previewAnchor()
                    if (next.screen !== preview.screen || next.position !== preview.edge || next.trigger.x !== preview.trigger.x || next.trigger.y !== preview.trigger.y || next.trigger.width !== preview.trigger.width)
                        preview.placement = next
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.withAlpha(Theme.surfaceContainerHigh, 1)
                radius: Theme.cornerRadius
                border.width: 1
                border.color: Theme.withAlpha(Theme.outline, 0.18)

                Column {
                    id: details
                    x: Theme.spacingM
                    y: Theme.spacingS
                    width: Math.max(0, parent.width - Theme.spacingM * 2)
                    spacing: Theme.spacingXS

                    StyledText {
                        width: parent.width
                        text: root.previewTitle
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        wrapMode: Text.Wrap
                        maximumLineCount: 6
                        elide: Text.ElideRight
                    }
                    StyledText {
                        width: parent.width
                        text: preview.due ? Qt.formatDateTime(new Date(taskController.dueTime(preview.due)), preview.due.kind === "date" ? "dddd d MMMM yyyy" : "dddd d MMMM yyyy · HH:mm") : ""
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.Wrap
                    }
                    StyledText {
                        width: parent.width
                        text: root.previewOverdue ? "Overdue" : (root.previewTask ? "Due in " + taskController.countdown(root.previewTask, false).replace(" ", "") : "")
                        font.pixelSize: Theme.fontSizeSmall
                        color: root.barCountdownColor
                    }
                    StyledText {
                        width: parent.width
                        text: root.previewTask?.list || ""
                        visible: text !== ""
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                    }
                    Row {
                        width: parent.width
                        spacing: Theme.spacingXS
                        visible: preview.location !== ""

                        DIcon {
                            name: "location_on"
                            size: Theme.iconSizeSmall
                            color: Theme.surfaceVariantText
                        }
                        StyledText {
                            width: parent.width - Theme.iconSizeSmall - Theme.spacingXS
                            text: preview.location
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DIcon {
                name: "checklist"
                size: root.iconSize
                color: root.barIconColor
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                visible: root.showBarCount
                text: taskController.countText + (root.showBarCountdown ? " ·" : "")
                color: Theme.surfaceText
                font.pixelSize: root.textSize
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                visible: root.showBarCountdown
                width: Math.min(implicitWidth, 180)
                text: root.showBarCountdown ? root.previewTitle.replace(/[\r\n\u2028\u2029]+/g, " ") : ""
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                color: Theme.surfaceText
                font.pixelSize: root.textSize
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                visible: root.showBarCountdown
                text: "•"
                color: root.barCountdownColor
                font.pixelSize: root.textSize
                font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                visible: root.showBarCountdown
                text: root.showBarCountdown ? taskController.countdown(root.previewTask, false).replace(" ", "") : ""
                color: root.barCountdownColor
                font.pixelSize: root.textSize
                font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
    verticalBarPill: Component {
        Column {
            spacing: 1

            DIcon {
                name: "checklist"
                size: root.iconSize
                color: root.barIconColor
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                visible: root.showBarCount
                text: taskController.countText
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                visible: root.showBarCountdown
                text: root.showBarCountdown ? taskController.countdown(root.previewTask, true) : ""
                color: root.barCountdownColor
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
    popoutContent: Component {
        PopoutComponent {
            id: popout

            readonly property real bodyHeight: Math.max(180, root.popoutHeight - headerHeight - (agendaHeader.visible ? agendaHeader.height : 0) - PopoutMetrics.contentPadding * 2)

            headerText: taskController.editing ? (taskController.identity ? "Edit task" : "New task") : ""

            Item {
                id: agendaHeader
                readonly property real actionSize: width < 336 ? 32 : 36
                readonly property bool stacked: width < 280
                width: popout.width
                height: stacked ? heading.implicitHeight + agendaActions.implicitHeight + Theme.spacingS * 2 : Math.max(48, heading.implicitHeight + Theme.spacingS * 2) + Theme.spacingS
                visible: !taskController.editing

                Column {
                    id: heading
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingS
                    anchors.right: agendaHeader.stacked ? parent.right : agendaActions.left
                    anchors.rightMargin: Theme.spacingXS
                    anchors.top: agendaHeader.stacked ? parent.top : undefined
                    anchors.verticalCenter: agendaHeader.stacked ? undefined : agendaActions.verticalCenter

                    StyledText {
                        width: parent.width
                        text: "Dank Tasks"
                        font.pixelSize: Theme.fontSizeLarge + 2
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                        Accessible.role: Accessible.Heading
                    }

                    StyledText {
                        width: parent.width
                        text: Qt.formatDate(new Date(taskController.clock), "dddd, d MMMM") + " · " + (taskController.refreshing ? "Refreshing…" : taskController.countText + " open")
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideRight
                    }
                }

                Flow {
                    id: agendaActions
                    width: Math.max(0, Math.min(agendaHeader.actionSize * 5, agendaHeader.width - Theme.spacingXS * 2))
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingXS
                    y: agendaHeader.stacked ? heading.height + Theme.spacingS : (agendaHeader.height - Theme.spacingS - height) / 2

                    DActionButton {
                        buttonSize: agendaHeader.actionSize
                        iconName: "add"
                        tooltipText: "Add task"
                        enabled: !taskController.busy && !taskController.unknownOutcome && !taskController.pendingRowAction
                        onClicked: {
                            agenda.closeFilters(false);
                            taskController.openNew();
                        }
                    }

                    DActionButton {
                        id: searchAction
                        buttonSize: agendaHeader.actionSize
                        iconName: "search"
                        iconColor: agenda.searchVisible ? Theme.primary : Theme.surfaceVariantText
                        tooltipText: agenda.searchVisible ? "Close search" : "Search tasks"
                        onClicked: {
                            agenda.closeFilters(false);
                            if (agenda.searchVisible) agenda.closeSearch();
                            else agenda.openSearch();
                        }

                        Connections {
                            target: agenda
                            function onSearchClosed() { searchAction.forceActiveFocus() }
                        }
                    }

                    DActionButton {
                        id: filterAction
                        buttonSize: agendaHeader.actionSize
                        iconName: "filter_list"
                        iconColor: agenda.filtersOpen || agenda.hasFilters ? Theme.primary : Theme.surfaceVariantText
                        tooltipText: agenda.filtersOpen ? "Hide filters" : "Show filters"
                        Accessible.description: agenda.hasFilters ? "Filters applied" : ""
                        onClicked: agenda.filtersOpen ? agenda.closeFilters(true) : agenda.openFilters(filterAction)

                        Connections {
                            target: agenda
                            function onFilterFocusRequested() { filterAction.forceActiveFocus() }
                        }
                    }

                    DActionButton {
                        buttonSize: agendaHeader.actionSize
                        iconName: "sync"
                        iconColor: taskController.refreshing ? Theme.primary : Theme.surfaceVariantText
                        tooltipText: "Refresh tasks"
                        enabled: !taskController.busy
                        onClicked: {
                            agenda.closeFilters(false);
                            taskController.refresh(true);
                        }
                    }

                    DActionButton {
                        buttonSize: agendaHeader.actionSize
                        iconName: "close"
                        tooltipText: "Close tasks"
                        onClicked: {
                            taskController.releaseAgenda(agenda);
                            if (popout.closePopout) popout.closePopout();
                            else root.closePopout();
                        }
                    }
                }
            }

            Keys.onPressed: event => {
                if (taskController.editing)
                    return;
                if (event.key === Qt.Key_F && event.modifiers === Qt.ControlModifier) {
                    agenda.closeFilters(false);
                    agenda.openSearch();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape && agenda.filtersOpen) {
                    agenda.closeFilters(true);
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
                        taskController.releaseAgenda(agenda);
                        agenda.closeFilters(false);
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