import QtQuick
import QtQuick.Controls
import qs.Common
import qs.DCommon.Widgets

Item {
    id: agenda
    required property var controller
    property bool filtersOpen: false
    onFiltersOpenChanged: if (filtersOpen) { scroller.stopMomentum(); scroller.contentY = 0 }
    implicitHeight: 440
    property var categories: {
        var result = []
        controller.tasks.forEach(function(t) { (t.categories || []).forEach(function(c) { if (result.indexOf(c) < 0) result.push(c) }) })
        return result.sort()
    }
    readonly property var sections: {
        var result = [], lastWeek = ""
        controller.groups.forEach(function(group) {
            if (group.key !== "upcoming" || controller.sortField !== "due") { result.push(group); return }
            var lastDay = "", current = null
            group.tasks.forEach(function(task) {
                var date = new Date(controller.dueTime(task.due)), day = date.toDateString()
                if (day !== lastDay) {
                    var monday = new Date(date.getFullYear(), date.getMonth(), date.getDate() - ((date.getDay() + 6) % 7))
                    var week = monday.toDateString()
                    var tomorrow = new Date(controller.clock); tomorrow.setDate(tomorrow.getDate() + 1)
                    current = {label: (day === tomorrow.toDateString() ? "Tomorrow · " : "") + Qt.formatDate(date, "dddd d MMMM"), week: week !== lastWeek ? "Week of " + Qt.formatDate(monday, "d MMMM") : "", tasks: []}
                    result.push(current); lastDay = day; lastWeek = week
                }
                current.tasks.push(task)
            })
        })
        return result
    }
    DFlickable {
        id: scroller
        anchors.fill: parent
        contentHeight: content.implicitHeight; clip: true; fadeEdges: false
        Column {
            id: content; width: parent.width; spacing: 4
            Column {
                width: parent.width; spacing: 6; visible: agenda.filtersOpen
                TodomanField { width: parent.width; placeholderText: "Search tasks"; text: agenda.controller.search; onTextEdited: if (inputFocused) agenda.controller.search = text; Accessible.name: "Search tasks" }
                TodomanCombo { width: parent.width; model: ["All lists"].concat(agenda.controller.viewLists); currentIndex: agenda.controller.viewList ? agenda.controller.viewLists.indexOf(agenda.controller.viewList) + 1 : 0; onActivated: index => agenda.controller.viewList = index ? agenda.controller.viewLists[index - 1] : ""; Accessible.name: "Filter by list" }
                TodomanCombo { width: parent.width; model: ["Open", "All", "Needs action", "In progress", "Completed", "Cancelled"]; currentIndex: ["open", "all", "NEEDS-ACTION", "IN-PROCESS", "COMPLETED", "CANCELLED"].indexOf(agenda.controller.viewStatus); onActivated: index => agenda.controller.viewStatus = ["open", "all", "NEEDS-ACTION", "IN-PROCESS", "COMPLETED", "CANCELLED"][index]; Accessible.name: "Status filter" }
                TodomanCombo { width: parent.width; model: ["All categories"].concat(agenda.categories); currentIndex: agenda.controller.category ? agenda.categories.indexOf(agenda.controller.category) + 1 : 0; onActivated: index => agenda.controller.category = index ? model[index] : ""; Accessible.name: "Category filter" }
                TodomanCombo { width: parent.width; model: ["Any priority", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]; currentIndex: agenda.controller.priorityFilter === "" ? 0 : Number(agenda.controller.priorityFilter) + 1; onActivated: index => agenda.controller.priorityFilter = index ? model[index] : ""; Accessible.name: "Priority filter" }
            }
            StyledText { width: parent.width; visible: agenda.controller.error !== ""; text: agenda.controller.error; color: Theme.error; wrapMode: Text.Wrap; font.pixelSize: Theme.fontSizeSmall }
            StyledText { visible: agenda.controller.unsupported.length > 0; width: parent.width; text: "Some task entries could not be read. The count and next-task suggestion may be incomplete."; wrapMode: Text.Wrap; color: Theme.error; font.pixelSize: Theme.fontSizeSmall }
            Repeater {
                model: agenda.controller.unsupported
                delegate: StyledText { required property var modelData; width: content.width; text: "Task " + modelData.id + (modelData.list ? " in " + modelData.list : "") + ": " + modelData.message; wrapMode: Text.Wrap; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall }
            }
            StyledText { visible: agenda.controller.visibleTasks.length === 0; width: parent.width; text: agenda.controller.loading ? "Loading tasks…" : "No matching tasks."; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeMedium }
            Repeater {
                model: agenda.sections
                delegate: Column {
                    required property var modelData
                    width: content.width; spacing: 0
                    Item {
                        width: parent.width; height: weekLabel.visible ? Math.max(30, weekLabel.implicitHeight + 12) : 0
                        StyledText { id: weekLabel; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; visible: !!modelData.week; text: modelData.week || ""; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall }
                        Rectangle { anchors.left: weekLabel.right; anchors.leftMargin: 8; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; visible: weekLabel.visible; height: 1; color: Theme.surfaceContainerHigh }
                    }
                    Item {
                        width: parent.width; height: Math.max(32, sectionLabel.implicitHeight + 12)
                        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; height: parent.height - 6; radius: 5; color: modelData.key === "today" ? Theme.withAlpha(Theme.primary, 0.16) : Theme.surfaceContainerHigh }
                        StyledText { id: sectionLabel; anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: modelData.label; color: modelData.key === "today" ? Theme.primary : Theme.surfaceText; font.pixelSize: Theme.fontSizeSmall }
                    }
                    Repeater { model: modelData.tasks; delegate: TodomanTaskRow { required property var modelData; width: content.width; task: modelData; controller: agenda.controller } }
                }
            }
        }
    }
}