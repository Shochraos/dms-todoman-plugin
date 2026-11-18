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
        for (const task of controller.tasks)
            for (const category of task.categories || [])
                values.add(category);
        if (controller.category)
            values.add(controller.category);
        return Array.from(values).sort();
    }
    readonly property bool hasFilters: filterFields.some(field => controller[field.field] !== defaultFilterValue(field.field))
    readonly property Item focusedItem: agenda.Window.window?.activeFocusItem ?? null
    readonly property var sections: {
        const result = [];
        const tomorrow = new Date(controller.clock);
        tomorrow.setDate(tomorrow.getDate() + 1);
        const tomorrowKey = tomorrow.toDateString();
        for (const group of controller.groups) {
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

    function revealFocusedItem() {
        const item = focusedItem;
        for (let ancestor = item; ancestor; ancestor = ancestor.parent) {
            if (ancestor === scroller.contentItem) {
                const top = item.mapToItem(scroller.contentItem, 0, 0).y;
                scroller.stopMomentum();
                scroller.revealRange(top - Theme.spacingXS, top + item.height + Theme.spacingXS);
                break;
            }
        }
    }

    onFiltersOpenChanged: if (filtersOpen) scrollToTop()
    onFocusedItemChanged: if (visible && focusedItem) revealFocusedItem()

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
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        fadeEdges: false
        onHeightChanged: if (agenda.visible && agenda.focusedItem) Qt.callLater(agenda.revealFocusedItem)

        Column {
            id: content

            width: scroller.width
            spacing: Theme.spacingS

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
                id: filterPanel

                readonly property real minimumFieldWidth: filterMetrics.advanceWidth("All categories") + Style.iconSize + Style.spacingXL * 2
                readonly property int columns: width >= minimumFieldWidth * 2 + spacing ? 2 : 1
                readonly property real fieldWidth: Math.max(0, (width - (columns - 1) * spacing) / columns)

                x: agenda.textInset
                width: Math.max(0, parent.width - agenda.textInset * 2)
                spacing: Theme.spacingS
                visible: agenda.filtersOpen

                FontMetrics {
                    id: filterMetrics
                    font.family: Style.fontFor("ui")
                    font.pixelSize: Style.fontSizeMedium
                }

                Repeater {
                    model: agenda.filterFields

                    delegate: Column {
                        id: filter

                        required property var modelData
                        width: filterPanel.fieldWidth
                        spacing: Theme.spacingXXS

                        StyledText {
                            text: filter.modelData.label
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            Accessible.ignored: true
                        }

                        DDropdown {
                            id: picker

                            width: filter.width
                            focusPolicy: Qt.StrongFocus
                            emptyText: filter.modelData.emptyLabel
                            Accessible.name: filter.modelData.label + " filter"
                            Accessible.description: currentValue ? labelOf(currentValue) : emptyText
                            optionValues: agenda.optionsFor(filter.modelData.field)
                            options: filter.modelData.field === "viewStatus" ? agenda.statusLabels : [emptyText].concat(optionValues.slice(1))
                            currentValue: agenda.controller[filter.modelData.field]
                            onValueChanged: value => {
                                agenda.controller[filter.modelData.field] = value;
                                picker.currentValue = Qt.binding(() => agenda.controller[filter.modelData.field]);
                            }
                            onVisibleChanged: if (!visible) closeDropdownMenu()
                        }
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
                text: agenda.controller.loading ? "Loading tasks…" : agenda.searchVisible && agenda.controller.search.trim() || agenda.hasFilters ? "No matching tasks." : agenda.defaultStatus === "open" ? "No open tasks." : "No tasks."
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

                    Item {
                        width: section.width
                        height: Math.max(28, sectionLabel.implicitHeight + Theme.spacingS)

                        Rectangle {
                            anchors.fill: parent
                            visible: section.isToday
                            color: Theme.withAlpha(Theme.primary, 0.16)
                            radius: Theme.cornerRadius / 2
                        }

                        StyledText {
                            id: sectionLabel

                            x: agenda.textInset
                            width: Math.max(0, parent.width - agenda.textInset * 2)
                            anchors.verticalCenter: parent.verticalCenter
                            text: section.modelData.label
                            color: section.isToday ? Theme.primary : Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.DemiBold
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
                        }
                    }
                }
            }
        }
    }
}
