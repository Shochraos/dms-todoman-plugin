import QtQuick
import QtQuick.Controls
import qs.Common
import qs.DCommon.Widgets

Column {
    id: editor
    required property var controller
    property bool scheduleExpanded: false
    property bool detailsExpanded: false
    property string destinationList: ""
    Connections { target: editor.controller; function onEditorSessionChanged() { editor.destinationList = "" } }
    height: 440
    spacing: Theme.spacingS
    StyledText { id: errorLabel; width: parent.width; visible: editor.controller.error !== ""; text: editor.controller.error; color: Theme.error; wrapMode: Text.Wrap }
    StyledText { id: outcomeLabel; width: parent.width; visible: editor.controller.unknownOutcome; text: "The outcome is unknown. Discard this draft, refresh and reopen the task before trying again."; color: Theme.error; wrapMode: Text.Wrap }
    Flickable {
        id: scroller; width: parent.width; height: Math.max(0, editor.height - (errorLabel.visible ? errorLabel.implicitHeight + editor.spacing : 0) - (outcomeLabel.visible ? outcomeLabel.implicitHeight + editor.spacing : 0) - (footer.visible ? footer.implicitHeight : discardFooter.implicitHeight) - editor.spacing); contentHeight: body.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { }
        Column {
            id: body; width: scroller.width; spacing: Theme.spacingS
            StyledText { color: Theme.surfaceText; font.pixelSize: Theme.fontSizeSmall; text: "Summary" }
            TodomanField { width: parent.width; text: editor.controller.draft ? editor.controller.draft.summary : ""; placeholderText: "Task summary"; onTextEdited: if (inputFocused) editor.controller.setField("summary", text); onAccepted: editor.controller.save(); Accessible.name: "Summary" }
            StyledText { color: Theme.surfaceText; font.pixelSize: Theme.fontSizeSmall; text: "List" }
            TodomanCombo { width: parent.width; property bool newTask: !editor.controller.identity; model: newTask ? ["Todoman default"].concat(editor.controller.lists) : editor.controller.lists; currentIndex: editor.controller.draft ? (newTask && !editor.controller.draft.list ? 0 : model.indexOf(editor.controller.draft.list, newTask ? 1 : 0)) : -1; onActivated: index => editor.controller.setField("list", newTask && index === 0 ? "" : model[index]); Accessible.name: "List" }
            TodomanButton { text: editor.scheduleExpanded ? "Hide schedule" : "Schedule and repeat"; onClicked: editor.scheduleExpanded = !editor.scheduleExpanded }
            Column {
            width: parent.width; spacing: Theme.spacingS; visible: editor.scheduleExpanded
            TodomanDatePicker { width: parent.width; label: "Start"; controller: editor.controller; fieldName: "start"; value: editor.controller.draft ? editor.controller.draft.start : null; onEdited: value => editor.controller.setField("start", value) }
            TodomanDatePicker { width: parent.width; label: "Due"; controller: editor.controller; fieldName: "due"; value: editor.controller.draft ? editor.controller.draft.due : null; onEdited: value => editor.controller.setField("due", value) }
            TodomanRecurrenceEditor { width: parent.width; session: editor.controller.editorSession; value: editor.controller.draft ? editor.controller.draft.rrule : ""; onEdited: value => editor.controller.setField("rrule", value) }
            }
            TodomanButton { text: editor.detailsExpanded ? "Hide details" : "Task details"; onClicked: editor.detailsExpanded = !editor.detailsExpanded }
            Column {
            width: parent.width; spacing: Theme.spacingS; visible: editor.detailsExpanded
            StyledText { color: Theme.surfaceText; font.pixelSize: Theme.fontSizeSmall; text: "Priority (0 = none, 1 = highest, 9 = lowest)"; wrapMode: Text.Wrap; width: parent.width }
            SpinBox { palette.text: Theme.surfaceText; palette.buttonText: Theme.surfaceText; palette.button: Theme.surfaceContainerHigh; palette.base: Theme.surfaceContainerHigh; palette.highlight: Theme.primary; from: 0; to: 9; value: editor.controller.draft ? editor.controller.draft.priority : 0; onValueModified: editor.controller.setField("priority", value); Accessible.name: "Priority" }
            StyledText { color: Theme.surfaceText; font.pixelSize: Theme.fontSizeSmall; text: "Status" }
            TodomanCombo { width: parent.width; model: ["Needs action", "In progress", "Completed", "Cancelled"]; currentIndex: editor.controller.draft ? Math.max(0, ["NEEDS-ACTION", "IN-PROCESS", "COMPLETED", "CANCELLED"].indexOf(editor.controller.draft.status)) : 0; onActivated: index => editor.controller.setField("status", ["NEEDS-ACTION", "IN-PROCESS", "COMPLETED", "CANCELLED"][index]); Accessible.name: "Status" }
            StyledText { color: Theme.surfaceText; font.pixelSize: Theme.fontSizeSmall; text: "Progress (%)" }
            SpinBox { palette.text: Theme.surfaceText; palette.buttonText: Theme.surfaceText; palette.button: Theme.surfaceContainerHigh; palette.base: Theme.surfaceContainerHigh; palette.highlight: Theme.primary; from: 0; to: 100; value: editor.controller.draft ? editor.controller.draft.percent : 0; onValueModified: editor.controller.setField("percent", value); Accessible.name: "Progress percent" }
            StyledText { color: Theme.surfaceText; font.pixelSize: Theme.fontSizeSmall; text: "Notes" }
            TextArea { width: parent.width; height: 90; color: Theme.surfaceText; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMedium; background: Rectangle { color: Theme.surfaceContainerHigh; radius: 6; border.width: parent.activeFocus ? 2 : 0; border.color: Theme.primary } wrapMode: TextEdit.Wrap; text: editor.controller.draft ? editor.controller.draft.description : ""; onTextChanged: if (activeFocus) editor.controller.setField("description", text); Accessible.name: "Notes" }
            StyledText { color: Theme.surfaceText; font.pixelSize: Theme.fontSizeSmall; text: "Categories (comma separated)" }
            TodomanField { width: parent.width; text: editor.controller.draft ? editor.controller.draft.categories.join(", ") : ""; onEditingFinished: if (editor.controller.draft && text !== editor.controller.draft.categories.join(", ")) editor.controller.setField("categories", text.split(",").map(function(s) { return s.trim() }).filter(function(s) { return s.length })); Accessible.name: "Categories" }
            StyledText { color: Theme.surfaceText; font.pixelSize: Theme.fontSizeSmall; text: "Location" }
            TodomanField { width: parent.width; text: editor.controller.draft ? editor.controller.draft.location : ""; onTextEdited: if (inputFocused) editor.controller.setField("location", text); Accessible.name: "Location" }
            }
            Flow {
                width: parent.width; spacing: 4; visible: !!editor.controller.identity
                TodomanButton { text: "Complete"; enabled: !editor.controller.busy && !editor.controller.dirty; onClicked: editor.controller.action("complete", editor.controller.identity) }
                TodomanButton { text: "Cancel task"; enabled: !editor.controller.busy && !editor.controller.dirty; onClicked: editor.controller.action("cancel", editor.controller.identity) }
                TodomanButton { text: "Reopen"; enabled: !editor.controller.busy && !editor.controller.dirty; onClicked: editor.controller.action("reopen", editor.controller.identity) }
                TodomanButton { text: "Delete"; enabled: !editor.controller.busy && !editor.controller.dirty; onClicked: editor.controller.confirmDelete = true }
            }
            Column {
                width: parent.width; spacing: 6; visible: !!editor.controller.identity
                TodomanCombo { id: targetList; width: parent.width; model: editor.controller.lists; currentIndex: model.indexOf(editor.destinationList) >= 0 ? model.indexOf(editor.destinationList) : model.length ? 0 : -1; onActivated: index => editor.destinationList = model[index]; Accessible.name: "Destination list" }
                Flow {
                    width: parent.width; spacing: 8
                    TodomanButton { text: "Move"; enabled: !editor.controller.busy && !editor.controller.dirty && targetList.currentText !== ""; onClicked: editor.controller.action("move", editor.controller.identity, targetList.currentText) }
                    TodomanButton { text: "Copy"; enabled: !editor.controller.busy && !editor.controller.dirty && targetList.currentText !== ""; onClicked: editor.controller.action("copy", editor.controller.identity, targetList.currentText) }
                }
            }
            Flow {
                visible: editor.controller.confirmDelete; spacing: 4
                width: parent.width
                StyledText { color: Theme.surfaceText; font.pixelSize: Theme.fontSizeSmall; text: "Permanently delete?" }
                TodomanButton { text: "Delete"; enabled: !editor.controller.busy; onClicked: editor.controller.action("delete", editor.controller.identity) }
                TodomanButton { text: "Keep"; onClicked: editor.controller.confirmDelete = false }
            }
        }
    }
    Row {
        id: footer; spacing: 8; visible: !editor.controller.confirmDiscard
        TodomanButton { text: "Cancel"; enabled: !editor.controller.busy; onClicked: editor.controller.leave() }
        TodomanButton { text: editor.controller.busy ? "Saving…" : "Save"; enabled: !editor.controller.busy && !editor.controller.unknownOutcome; onClicked: editor.controller.save() }
    }
    Flow {
        id: discardFooter; width: parent.width; spacing: 8; visible: editor.controller.confirmDiscard
        StyledText { color: Theme.surfaceText; font.pixelSize: Theme.fontSizeSmall; text: "Discard unsaved changes?" }
        TodomanButton { text: "Discard"; onClicked: editor.controller.discard() }
        TodomanButton { text: "Keep editing"; onClicked: editor.controller.confirmDiscard = false }
    }
}
