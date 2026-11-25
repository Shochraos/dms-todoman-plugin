import QtQuick
import QtQuick.Window
import qs.Common
import qs.DCommon.Common
import qs.DCommon.Widgets

Item {
    id: agenda

    required property var controller
    property bool searchOpen: false
    property bool filtersOpen: false
    property Item filterAnchor: null
    readonly property bool searchVisible: searchOpen || controller.search !== ""
    readonly property real textInset: Theme.spacingS
    readonly property string defaultStatus: controller.showCompleted ? "all" : "open"
    readonly property var filterFields: [
        {field: "viewList", label: "List", emptyLabel: "All lists"},
        {field: "viewStatus", label: "Status", emptyLabel: ""},
        {field: "category", label: "Category", emptyLabel: "All categories"},
        {field: "priorityFilter", label: "Priority", emptyLabel: "Any priority"}
    ]
    readonly property var statusValues: ["open", "all", "NEEDS-ACTION", "IN-PROCESS", "COMPLETED", "CANCELLED"]
    readonly property var statusLabels: ["Open", "All statuses", "Needs action", "In progress", "Completed", "Cancelled"]
    readonly property var priorityValues: ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
    readonly property var categories: {
        const values = new Set();
        for (const task of controller.tasks) {
            if (!controller.visibleByStart(task))
                continue;
            for (const category of task.categories || [])
                values.add(category);
        }
        if (controller.category)
            values.add(controller.category);
        return Array.from(values).sort();
    }
    readonly property bool hasFilters: filterFields.some(field => controller[field.field] !== defaultFilterValue(field.field))
    readonly property Item focusedItem: agenda.Window.window?.activeFocusItem ?? null
    readonly property var nextTask: {
        let next = null;
        let nearestDue = Infinity;
        for (const task of controller.visibleTasks) {
            if (!controller.isOpen(task) || !task.due)
                continue;
            const due = controller.dueTime(task.due);
            if (due > controller.clock && due < nearestDue) {
                next = task;
                nearestDue = due;
            }
        }
        return next;
    }
    readonly property var sections: {
        const result = [];
        const tomorrow = new Date(controller.clock);
        tomorrow.setDate(tomorrow.getDate() + 1);
        const tomorrowKey = tomorrow.toDateString();
        for (const group of controller.groups) {
            if (group.key === "today") {
                result.push({key: group.key, label: "Today · " + Qt.formatDate(new Date(controller.clock), "dddd d MMMM"), tasks: group.tasks});
                continue;
            }
            if (group.key !== "upcoming" || controller.sortField !== "due") {
                result.push(group);
                continue;
            }
            let lastDay = "";
            let section = null;
            for (const task of group.tasks) {
                const date = new Date(controller.dueTime(task.due));
                const day = date.toDateString();
                if (day !== lastDay) {
                    section = {
                        key: "upcoming",
                        label: (day === tomorrowKey ? "Tomorrow · " : "") + Qt.formatDate(date, "dddd d MMMM"),
                        tasks: []
                    };
                    result.push(section);
                    lastDay = day;
                }
                section.tasks.push(task);
            }
        }
        return result;
    }

    signal searchClosed()
    signal filterFocusRequested()

    function defaultFilterValue(field) {
        return field === "viewStatus" ? defaultStatus : "";
    }

    function optionsFor(field) {
        switch (field) {
        case "viewList": return [""].concat(controller.viewLists);
        case "viewStatus": return statusValues;
        case "category": return [""].concat(categories);
        case "priorityFilter": return [""].concat(priorityValues);
        }
        return [];
    }

    function scrollToTop() {
        scroller.stopMomentum();
        scroller.contentY = 0;
    }

    function openSearch() {
        searchOpen = true;
        scrollToTop();
        searchField.forceActiveFocus();
    }

    function closeSearch() {
        controller.search = "";
        searchOpen = false;
        scrollToTop();
        searchClosed();
    }

    function openFilters(anchor: Item) {
        filterAnchor = anchor;
        filtersOpen = true;
        scroller.stopMomentum();
        menuScroll.contentY = 0;
        filterRows.itemAt(0)?.picker.focusTarget.forceActiveFocus(Qt.TabFocusReason);
    }

    function closeFilters(restoreFocus: bool) {
        if (!filtersOpen)
            return;
        filtersOpen = false;
        filterAnchor = null;
        if (restoreFocus)
            filterFocusRequested();
    }

    function revealFocusedItem() {
        const item = focusedItem;
        for (let ancestor = item; ancestor; ancestor = ancestor.parent) {
            const viewport = ancestor === scroller.contentItem ? scroller : ancestor === menuScroll.contentItem ? menuScroll : null;
            if (viewport) {
                const top = item.mapToItem(viewport.contentItem, 0, 0).y;
                viewport.stopMomentum();
                viewport.revealRange(top - Theme.spacingXS, top + item.height + Theme.spacingXS);
                break;
            }
        }
    }

    onFocusedItemChanged: if (visible && focusedItem) revealFocusedItem()
    onVisibleChanged: {
        if (!visible) {
            controller.releaseAgenda(agenda);
            closeFilters(false);
        }
    }
    Component.onDestruction: controller?.releaseAgenda(agenda)

    Connections {
        target: agenda.controller

        function onErrorChanged() {
            if (agenda.visible && agenda.controller.error)
                agenda.scrollToTop();
        }
    }

    Item {
        id: searchStrip

        width: parent.width
        height: agenda.searchVisible ? searchField.implicitHeight + Theme.spacingS : 0
        visible: agenda.searchVisible
        enabled: !agenda.filtersOpen

        DSearchField {
            id: searchField

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: agenda.textInset
            placeholderText: "Search tasks"
            Accessible.name: "Search tasks"
            text: agenda.controller.search
            onTextEdited: {
                if (inputFocused && text !== agenda.controller.search) {
                    agenda.controller.search = text;
                    agenda.scrollToTop();
                }
            }
            onCleared: {
                agenda.searchOpen = true;
                agenda.controller.search = "";
                agenda.scrollToTop();
                forceActiveFocus();
            }
            Keys.onEscapePressed: agenda.closeSearch()
        }
    }

    DFlickable {
        id: scroller

        anchors.top: searchStrip.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: agenda.textInset
        anchors.rightMargin: agenda.textInset
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        enabled: !agenda.filtersOpen
        onHeightChanged: if (agenda.visible && agenda.focusedItem) Qt.callLater(agenda.revealFocusedItem)

        Column {
            id: content

            width: scroller.width
            spacing: Theme.spacingXS

            Column {
                x: agenda.textInset
                width: Math.max(0, parent.width - agenda.textInset * 2)
                spacing: Theme.spacingXS

                StyledText {
                    width: parent.width
                    visible: text !== ""
                    text: agenda.controller.error
                    textFormat: Text.PlainText
                    color: Theme.error
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeSmall
                }

                StyledText {
                    width: parent.width
                    visible: agenda.controller.unknownOutcome
                    text: "A task change could not be confirmed. Use Refresh to reload all watched tasks before making another change."
                    color: Theme.error
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeSmall
                }

                StyledText {
                    width: parent.width
                    visible: agenda.controller.unsupported.length > 0
                    text: "Some task entries could not be read. The count and next-task suggestion may be incomplete."
                    color: Theme.error
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeSmall
                }

                Repeater {
                    model: agenda.controller.unsupported

                    delegate: StyledText {
                        required property var modelData

                        width: parent.width
                        text: "Task " + modelData.id + (modelData.list ? " in " + modelData.list : "") + ": " + modelData.message
                        textFormat: Text.PlainText
                        color: Theme.surfaceVariantText
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }

            Flow {
                id: appliedFilters

                x: agenda.textInset
                width: Math.max(0, parent.width - agenda.textInset * 2)
                spacing: Theme.spacingXS
                visible: agenda.hasFilters

                Repeater {
                    model: agenda.filterFields

                    delegate: DButton {
                        required property var modelData
                        readonly property string value: agenda.controller[modelData.field]
                        readonly property string valueLabel: modelData.field === "viewStatus" ? agenda.statusLabels[agenda.statusValues.indexOf(value)] || value : value

                        visible: value !== agenda.defaultFilterValue(modelData.field)
                        text: modelData.label + ": " + valueLabel
                        iconName: "close"
                        variant: "tonal"
                        buttonHeight: 40
                        horizontalPadding: Theme.spacingS
                        maximumWidth: appliedFilters.width
                        wrapText: true
                        tooltipText: "Remove " + modelData.label.toLowerCase() + " filter"
                        Accessible.name: tooltipText + ": " + valueLabel
                        onClicked: {
                            agenda.controller[modelData.field] = agenda.defaultFilterValue(modelData.field);
                            agenda.filterFocusRequested();
                        }
                    }
                }
            }

            StyledText {
                x: agenda.textInset
                width: Math.max(0, parent.width - agenda.textInset * 2)
                topPadding: Theme.spacingS
                visible: agenda.controller.visibleTasks.length === 0 && !agenda.controller.error
                text: agenda.controller.loading ? "Loading tasks…" : agenda.searchVisible && agenda.controller.search.trim() || agenda.hasFilters ? "No matching tasks." : agenda.controller.hiddenFutureCount > 0 ? "No startable tasks (" + agenda.controller.hiddenFutureCount + " scheduled for later)." : agenda.defaultStatus === "open" ? "No open tasks." : "No tasks."
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeMedium
                wrapMode: Text.Wrap
            }

            Repeater {
                model: agenda.sections

                delegate: Column {
                    id: section

                    required property var modelData
                    readonly property bool isToday: modelData.key === "today"
                    width: content.width
                    spacing: Theme.spacingXXS

                    Rectangle {
                        width: section.width
                        height: Math.max(26, sectionLabel.implicitHeight + Theme.spacingXS * 2)
                        color: section.isToday ? Theme.withAlpha(Theme.primary, 0.16) : Theme.surfaceContainerHigh
                        radius: Theme.cornerRadiusS

                        StyledText {
                            id: sectionLabel

                            x: agenda.textInset
                            width: Math.max(0, parent.width - agenda.textInset * 2)
                            anchors.verticalCenter: parent.verticalCenter
                            text: section.modelData.label
                            color: section.isToday ? Theme.primary : Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            Accessible.role: Accessible.Heading
                        }
                    }

                    Repeater {
                        model: section.modelData.tasks

                        delegate: TodomanTaskRow {
                            required property var modelData

                            width: section.width
                            textInset: agenda.textInset
                            task: modelData
                            controller: agenda.controller
                            ownerAgenda: agenda
                            highlighted: modelData.id === agenda.nextTask?.id && modelData.uid === agenda.nextTask?.uid
                        }
                    }
                }
            }
        }
    }

    FocusScope {
        anchors.fill: parent
        z: 1
        visible: agenda.filtersOpen

        MouseArea {
            anchors.fill: parent
            onClicked: agenda.closeFilters(true)
        }

        Rectangle {
            readonly property point anchorTop: agenda.filterAnchor ? agenda.filterAnchor.mapToItem(agenda, agenda.filterAnchor.width / 2, agenda.filterAnchor.height) : Qt.point(agenda.width, 0)
            x: Math.max(0, Math.min(agenda.width - width - agenda.textInset, anchorTop.x - width / 2))
            y: Math.max(0, anchorTop.y)
            width: Math.max(0, Math.min(agenda.width - agenda.textInset * 2, Math.max(248, Theme.fontSizeMedium * 16)))
            height: Math.min(menuContent.implicitHeight + Theme.spacingXS * 2, Math.max(0, agenda.height - y))
            color: Theme.surfaceContainerHigh
            radius: Theme.cornerRadiusS
            border.width: 1
            border.color: Theme.withAlpha(Theme.outline, 0.32)

            MouseArea { anchors.fill: parent }

            DFlickable {
                id: menuScroll
                anchors.fill: parent
                anchors.margins: Theme.spacingXS
                contentWidth: width
                contentHeight: menuContent.implicitHeight
                fadeEdges: false
                clip: true
                onHeightChanged: if (agenda.filtersOpen) Qt.callLater(agenda.revealFocusedItem)

                Column {
                    id: menuContent
                    width: menuScroll.width

                    Repeater {
                        id: filterRows
                        model: agenda.filterFields
                        delegate: FilterRow { width: menuContent.width }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.withAlpha(Theme.outline, 0.25)
                    }

                    DButton {
                        anchors.right: parent.right
                        text: "Reset filters"
                        variant: "text"
                        buttonHeight: Math.max(36, Theme.fontSizeMedium + Theme.spacingS * 2)
                        maximumWidth: menuContent.width
                        wrapText: true
                        onClicked: {
                            for (const filter of agenda.filterFields)
                                agenda.controller[filter.field] = agenda.defaultFilterValue(filter.field);
                        }
                    }
                }
            }
        }
    }

    component FilterRow: Item {
        id: filter
        required property var modelData
        property alias picker: chooser
        height: chooser.triggerHeight

        StyledText {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingS
            anchors.right: chooser.left
            anchors.verticalCenter: parent.verticalCenter
            text: filter.modelData.label
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Medium
            elide: Text.ElideRight
            Accessible.ignored: true
        }

        DDropdown {
            id: chooser
            anchors.right: parent.right
            width: filter.width * 0.70
            triggerHeight: Math.max(36, Theme.fontSizeMedium + Theme.spacingS * 2)
            backgroundColor: "transparent"
            normalBorderColor: "transparent"
            focusedBorderColor: activeFocus ? Theme.primary : "transparent"
            focusPolicy: Qt.StrongFocus
            alignPopupRight: true
            emptyText: filter.modelData.emptyLabel
            Accessible.name: filter.modelData.label + " filter"
            Accessible.description: currentValue ? labelOf(currentValue) : emptyText
            optionValues: agenda.optionsFor(filter.modelData.field)
            options: filter.modelData.field === "viewStatus" ? agenda.statusLabels : [emptyText].concat(optionValues.slice(1))
            currentValue: agenda.controller[filter.modelData.field]
            onValueChanged: value => {
                agenda.controller[filter.modelData.field] = value;
                chooser.currentValue = Qt.binding(() => agenda.controller[filter.modelData.field]);
            }
            onVisibleChanged: if (!visible) closeDropdownMenu()
        }
    }
}
