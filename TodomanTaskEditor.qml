import QtQuick
import QtQuick.Controls
import QtQuick.Window
import qs.Common
import qs.DCommon.Widgets

Item {
    id: editor

    required property var controller
    property bool scheduleExpanded: false
    property bool detailsExpanded: false
    property bool actionsExpanded: false
    property string destinationList: ""
    readonly property var draft: controller.draft
    readonly property bool canAct: !!controller.identity && !controller.busy && !controller.dirty && !controller.unknownOutcome
    readonly property bool canSave: !!draft && !controller.busy && !controller.unknownOutcome && !controller.confirmDiscard && !controller.confirmDelete
    readonly property bool saving: controller.busy && ["save", "create"].includes(controller.activeRequest?.action)
    readonly property Item focusedItem: editor.Window.window?.activeFocusItem ?? null
    readonly property real inset: Math.max(Theme.spacingXS, Theme.focusRingWidth + Theme.focusRingOffset)
    readonly property var statuses: ["NEEDS-ACTION", "IN-PROCESS", "COMPLETED", "CANCELLED"]
    property Item discardReturnFocus: null

    height: 440

    onVisibleChanged: {
        if (visible && controller?.draft)
            Qt.callLater(() => { if (visible && controller.draft) summaryField.forceActiveFocus(); });
    }

    Connections {
        target: editor.controller

        function onEditorSessionChanged() {
            editor.scheduleExpanded = false;
            editor.detailsExpanded = false;
            editor.actionsExpanded = false;
            editor.destinationList = "";
            editor.discardReturnFocus = null;
            categories.pending = false;
            scroller.cancelFlick();
            scroller.contentY = 0;
        }

        function onConfirmDiscardChanged() {
            if (editor.controller.confirmDiscard)
                Qt.callLater(keepEditing.forceActiveFocus, Qt.TabFocusReason);
        }

        function onConfirmDeleteChanged() {
            if (editor.controller.confirmDelete) {
                editor.actionsExpanded = true;
                Qt.callLater(keepTask.forceActiveFocus, Qt.TabFocusReason);
            }
        }
    }

    onFocusedItemChanged: Qt.callLater(revealFocus)

    function revealFocus() {
        const item = focusedItem;
        if (!visible || !item || !item.visible || scroller.height <= 0)
            return;
        let container = item;
        let ancestor = item.parent;
        while (ancestor && ancestor !== body) {
            if (ancestor instanceof DTextEdit || ancestor instanceof DTextField || ancestor instanceof SpinBox)
                container = ancestor;
            ancestor = ancestor.parent;
        }
        if (ancestor !== body)
            return;
        const top = container.mapToItem(scroller.contentItem, 0, 0).y;
        scroller.revealRange(top - inset, top + container.height + inset);
    }

    function save() {
        if (!canSave)
            return;
        categories.commit();
        controller.save();
    }

    function leave() {
        categories.commit();
        discardReturnFocus = focusedItem;
        controller.leave();
    }

    function keepDraft() {
        controller.confirmDiscard = false;
        if (discardReturnFocus?.visible && discardReturnFocus.enabled)
            discardReturnFocus.forceActiveFocus(Qt.TabFocusReason);
        else
            cancelButton.forceActiveFocus(Qt.TabFocusReason);
        discardReturnFocus = null;
    }

    component FieldGroup: Column {
        property string label: ""
        width: parent.width
        spacing: Theme.spacingXS

        StyledText {
            width: parent.width
            text: parent.label
            visible: text !== ""
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            wrapMode: Text.Wrap
        }
    }

    component FormDropdown: DDropdown {
        property string selectedValue: ""
        width: parent.width
        dropdownWidth: width
        clampMenuWidth: true
        triggerHeight: Math.max(Theme.buttonHeightS, Theme.fontSizeMedium + Theme.spacingM * 2)
        focusPolicy: Qt.StrongFocus
        currentValue: selectedValue
        onSelectedValueChanged: currentValue = selectedValue
        onValueChanged: currentValue = selectedValue
    }

    component FlatButton: StyledButton {
        id: rowButton

        property string iconName: ""
        property color labelColor: Theme.surfaceText
        width: parent.width
        implicitHeight: Math.max(Theme.buttonHeightXS, caption.implicitHeight + Theme.spacingS * 2)
        radius: Theme.cornerRadiusS
        Accessible.name: text

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: parent.pressed ? Theme.surfaceContainerHighest : parent.hovered ? Theme.surfaceContainerHigh : "transparent"
            visible: parent.enabled
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: Math.max(1, Theme.focusRingWidth)
            border.color: Theme.primary
            visible: rowButton.visualFocus
        }

        StyledText {
            id: caption
            anchors.left: parent.left
            anchors.right: rowButton.iconName ? rowIcon.left : parent.right
            anchors.margins: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            wrapMode: Text.Wrap
            text: rowButton.text
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: rowButton.enabled ? rowButton.labelColor : Theme.surfaceVariantText
            opacity: rowButton.enabled ? 1 : 0.6
        }

        DIcon {
            id: rowIcon
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            name: rowButton.iconName
            size: Theme.iconSizeMedium
            color: Theme.surfaceVariantText
            visible: name !== ""
        }
    }

    component Disclosure: Column {
        id: disclosure

        property alias text: disclosureButton.text
        property bool expanded: false
        signal toggled
        width: parent.width

        Rectangle {
            width: parent.width
            height: Math.max(1, Theme.outlineWidth)
            color: Theme.outlineVariant
        }

        FlatButton {
            id: disclosureButton
            iconName: disclosure.expanded ? "expand_less" : "expand_more"
            checkable: true
            checked: disclosure.expanded
            Accessible.checkable: true
            Accessible.checked: checked
            onClicked: disclosure.toggled()
        }
    }

    component QuietButton: DButton {
        variant: "text"
        textColor: Theme.surfaceVariantText
        buttonHeight: Math.max(Theme.buttonHeightS, Theme.fontSizeMedium + Theme.spacingM)
    }

    component FormNumber: SpinBox {
        id: numberField
        width: Math.min(parent.width, Math.max(implicitWidth, Theme.fontSizeMedium * 8))
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeMedium
        editable: true
        palette.text: Theme.surfaceText
        palette.buttonText: Theme.surfaceText
        palette.button: Theme.surfaceContainerHigh
        palette.base: Theme.surfaceContainerHigh
        palette.highlight: Theme.primary
        palette.highlightedText: Theme.onPrimary

        background: Rectangle {
            color: Theme.surfaceContainerHigh
            radius: Theme.cornerRadiusS
            border.color: numberField.activeFocus ? Theme.primary : Theme.outlineVariant
            border.width: numberField.activeFocus ? 2 : 1
        }
    }

    DFlickable {
        id: feedback
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: editor.inset
        anchors.rightMargin: editor.inset
        visible: editor.controller.error !== "" || editor.controller.unknownOutcome
        height: visible ? Math.min(messageColumn.implicitHeight, Math.max(0, (editor.height - footer.height) / 3)) : 0
        contentHeight: messageColumn.implicitHeight
        contentWidth: width
        clip: true
        fadeEdges: false
        activeFocusOnTab: visible && contentHeight > height
        Accessible.name: "Task editor messages"
        Keys.onUpPressed: contentY = Math.max(0, contentY - Theme.spacingM)
        Keys.onDownPressed: contentY = Math.min(contentHeight - height, contentY + Theme.spacingM)

        Rectangle {
            parent: feedback
            anchors.fill: parent
            z: 1
            color: "transparent"
            border.width: feedback.activeFocus ? Math.max(1, Theme.focusRingWidth) : 0
            border.color: Theme.primary
        }

        Column {
            id: messageColumn
            width: Math.max(0, feedback.width - Theme.spacingS)
            spacing: Theme.spacingXS

            StyledText {
                id: errorMessage
                width: parent.width
                visible: editor.controller.error !== ""
                text: editor.controller.error
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.error
                onTextChanged: {
                    feedback.contentY = 0;
                    if (editor.visible && errorMessage.text) Accessible.announce(errorMessage.text, Accessible.Assertive);
                }
            }

            StyledText {
                width: parent.width
                visible: editor.controller.unknownOutcome
                text: "The outcome is unknown. Discard this draft, refresh and reopen the task before trying again."
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.error
            }
        }
    }

    DFlickable {
        id: scroller
        anchors.top: feedback.bottom
        anchors.bottom: footer.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: feedback.visible ? Theme.spacingS : 0
        clip: true
        fadeEdges: false
        contentWidth: width
        contentHeight: body.y + body.implicitHeight + editor.inset
        enabled: !editor.controller.confirmDiscard

        Column {
            id: body
            x: editor.inset
            y: editor.inset
            width: Math.max(0, scroller.width - editor.inset * 2 - Theme.spacingS)
            spacing: Theme.spacingM

            FieldGroup {
                label: "Summary"

                TodomanField {
                    id: summaryField
                    width: parent.width
                    text: editor.draft?.summary ?? ""
                    placeholderText: "Task summary"
                    Accessible.name: "Summary"
                    onTextEdited: if (inputFocused && editor.draft && text !== editor.draft.summary) editor.controller.setField("summary", text)
                    onAccepted: editor.save()
                }
            }

            FieldGroup {
                label: "List"

                FormDropdown {
                    readonly property bool newTask: !editor.controller.identity
                    options: newTask ? ["Todoman default"].concat(editor.controller.lists) : editor.controller.lists
                    optionValues: newTask ? [""].concat(editor.controller.lists) : editor.controller.lists
                    selectedValue: editor.draft?.list ?? ""
                    emptyText: newTask ? "Todoman default" : ""
                    Accessible.name: "List"
                    onValueChanged: value => { if (editor.draft) editor.controller.setField("list", value); }
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingM

                Column {
                    width: parent.width
                    spacing: editor.scheduleExpanded ? Theme.spacingM : 0

                    Disclosure {
                        text: "Schedule"
                        expanded: editor.scheduleExpanded
                        onToggled: editor.scheduleExpanded = !editor.scheduleExpanded
                    }

                    Column {
                        width: parent.width
                        visible: editor.scheduleExpanded
                        spacing: Theme.spacingM

                        TodomanDatePicker {
                            width: parent.width
                            label: "Start"
                            controller: editor.controller
                            fieldName: "start"
                            value: editor.draft?.start ?? null
                            onEdited: value => editor.controller.setField("start", value)
                        }

                        TodomanDatePicker {
                            width: parent.width
                            label: "Due"
                            controller: editor.controller
                            fieldName: "due"
                            value: editor.draft?.due ?? null
                            onEdited: value => editor.controller.setField("due", value)
                        }

                        TodomanRecurrenceEditor {
                            width: parent.width
                            session: editor.controller.editorSession
                            value: editor.draft?.rrule ?? ""
                            onEdited: value => editor.controller.setField("rrule", value)
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: editor.detailsExpanded ? Theme.spacingM : 0

                    Disclosure {
                        text: "Details"
                        expanded: editor.detailsExpanded
                        onToggled: editor.detailsExpanded = !editor.detailsExpanded
                    }

                    Column {
                        width: parent.width
                        visible: editor.detailsExpanded
                        spacing: Theme.spacingM

                        FieldGroup {
                            label: "Priority"

                            FormNumber {
                                from: 0
                                to: 9
                                value: editor.draft?.priority ?? 0
                                Accessible.name: "Priority"
                                Accessible.description: "0 is none, 1 is highest, 9 is lowest."
                                onValueModified: editor.controller.setField("priority", value)
                            }

                            StyledText {
                                width: parent.width
                                text: "0: none, 1: highest, 9: lowest"
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                                wrapMode: Text.Wrap
                            }
                        }

                        FieldGroup {
                            label: "Status"

                            FormDropdown {
                                options: ["Needs action", "In progress", "Completed", "Cancelled"]
                                optionValues: editor.statuses
                                selectedValue: editor.statuses.includes(editor.draft?.status) ? editor.draft.status : editor.statuses[0]
                                Accessible.name: "Status"
                                onValueChanged: value => editor.controller.setField("status", value)
                            }
                        }

                        FieldGroup {
                            label: "Progress (%)"

                            FormNumber {
                                from: 0
                                to: 100
                                value: editor.draft?.percent ?? 0
                                Accessible.name: "Progress percent"
                                onValueModified: editor.controller.setField("percent", value)
                            }
                        }

                        FieldGroup {
                            label: "Notes"

                            DTextEdit {
                                width: parent.width
                                text: editor.draft?.description ?? ""
                                placeholderText: "Add notes"
                                Accessible.name: "Notes"
                                onTextEdited: {
                                    if (getActiveFocus() && editor.draft && text !== editor.draft.description)
                                        editor.controller.setField("description", text);
                                }
                            }
                        }

                        FieldGroup {
                            label: "Categories"

                            TodomanField {
                                id: categories
                                property bool pending: false
                                width: parent.width
                                text: editor.draft?.categories?.join(", ") ?? ""
                                placeholderText: "Separate with commas"
                                Accessible.name: "Categories"
                                Accessible.description: "Separate categories with commas."
                                onTextEdited: pending = true
                                onEditingFinished: commit()

                                function commit() {
                                    if (!pending)
                                        return;
                                    pending = false;
                                    if (editor.draft && text !== (editor.draft.categories || []).join(", "))
                                        editor.controller.setField("categories", text.split(",").map(category => category.trim()).filter(category => category.length));
                                }
                            }
                        }

                        FieldGroup {
                            label: "Location"

                            TodomanField {
                                width: parent.width
                                text: editor.draft?.location ?? ""
                                Accessible.name: "Location"
                                onTextEdited: if (inputFocused && editor.draft) editor.controller.setField("location", text)
                            }
                        }
                    }
                }

                Column {
                    width: parent.width
                    visible: !!editor.controller.identity
                    spacing: editor.actionsExpanded ? Theme.spacingM : 0

                    Disclosure {
                        text: "Task actions"
                        expanded: editor.actionsExpanded
                        enabled: !editor.controller.confirmDelete
                        onToggled: editor.actionsExpanded = !editor.actionsExpanded
                    }

                    Column {
                        width: parent.width
                        visible: editor.actionsExpanded
                        spacing: Theme.spacingM

                        StyledText {
                            width: parent.width
                            visible: editor.controller.dirty
                            text: "Save your changes before using task actions."
                            wrapMode: Text.Wrap
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }

                        Column {
                            readonly property bool taskCompleted: !!editor.controller.identity && editor.controller.identity.completed === true
                            readonly property bool taskCancelled: !!editor.controller.draftBaseline && editor.controller.draftBaseline.status === "CANCELLED"
                            readonly property bool taskOpen: !taskCompleted && !taskCancelled
                            width: parent.width
                            enabled: editor.canAct && !editor.controller.confirmDelete

                            FlatButton {
                                text: "Complete"
                                visible: parent.taskOpen
                                onClicked: editor.controller.action("complete", editor.controller.identity)
                            }

                            FlatButton {
                                text: "Cancel task"
                                visible: !parent.taskCancelled
                                onClicked: editor.controller.action("cancel", editor.controller.identity)
                            }

                            FlatButton {
                                text: "Reopen"
                                visible: !parent.taskOpen
                                onClicked: editor.controller.action("reopen", editor.controller.identity)
                            }
                        }

                        FieldGroup {
                            label: "Destination list"
                            enabled: editor.canAct && !editor.controller.confirmDelete

                            FormDropdown {
                                id: targetList
                                options: editor.controller.lists
                                selectedValue: options.includes(editor.destinationList) ? editor.destinationList : options[0] ?? ""
                                Accessible.name: "Destination list"
                                onValueChanged: value => editor.destinationList = value
                            }

                            Flow {
                                width: parent.width
                                spacing: Theme.spacingS

                                QuietButton {
                                    text: "Move"
                                    maximumWidth: parent.width
                                    enabled: targetList.selectedValue !== ""
                                    onClicked: editor.controller.action("move", editor.controller.identity, targetList.selectedValue)
                                }

                                QuietButton {
                                    text: "Copy"
                                    maximumWidth: parent.width
                                    enabled: targetList.selectedValue !== ""
                                    onClicked: editor.controller.action("copy", editor.controller.identity, targetList.selectedValue)
                                }
                            }
                        }

                        FlatButton {
                            id: deleteButton
                            text: "Delete…"
                            labelColor: Theme.error
                            visible: !editor.controller.confirmDelete
                            enabled: editor.canAct
                            onClicked: editor.controller.confirmDelete = true
                        }

                        Column {
                            width: parent.width
                            visible: editor.controller.confirmDelete
                            spacing: Theme.spacingXS

                            StyledText {
                                width: parent.width
                                text: "Permanently delete this task?"
                                color: Theme.error
                                wrapMode: Text.Wrap
                            }

                            Flow {
                                width: parent.width
                                spacing: Theme.spacingS

                                QuietButton {
                                    id: keepTask
                                    text: "Keep task"
                                    maximumWidth: parent.width
                                    enabled: !editor.controller.busy
                                    onClicked: {
                                        editor.controller.confirmDelete = false;
                                        deleteButton.forceActiveFocus(Qt.TabFocusReason);
                                    }
                                }

                                DButton {
                                    text: "Delete task"
                                    danger: true
                                    variant: "tonal"
                                    maximumWidth: parent.width
                                    enabled: editor.canAct
                                    onClicked: editor.controller.action("delete", editor.controller.identity)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Column {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: editor.inset
        anchors.rightMargin: editor.inset
        spacing: Theme.spacingS
        bottomPadding: editor.inset

        Rectangle {
            width: parent.width
            height: Math.max(1, Theme.outlineWidth)
            color: Theme.outlineVariant
        }

        StyledText {
            visible: editor.controller.confirmDiscard
            width: parent.width
            text: "Discard unsaved changes?"
            wrapMode: Text.Wrap
        }

        Flow {
            anchors.right: parent.right
            width: Math.min(parent.width, cancelButton.implicitWidth + saveButton.implicitWidth + spacing)
            spacing: Theme.spacingS
            visible: !editor.controller.confirmDiscard

            QuietButton {
                id: cancelButton
                text: "Cancel"
                maximumWidth: footer.width
                enabled: !editor.controller.busy
                onClicked: editor.leave()
            }

            DButton {
                id: saveButton
                text: editor.saving ? "Saving…" : "Save"
                reserveText: "Saving…"
                iconName: "check"
                maximumWidth: footer.width
                buttonHeight: Math.max(Theme.buttonHeightS, Theme.fontSizeMedium + Theme.spacingM)
                enabled: editor.canSave
                onClicked: editor.save()
            }
        }

        Flow {
            anchors.right: parent.right
            width: Math.min(parent.width, keepEditing.implicitWidth + discardButton.implicitWidth + spacing)
            spacing: Theme.spacingS
            visible: editor.controller.confirmDiscard

            QuietButton {
                id: keepEditing
                text: "Keep editing"
                maximumWidth: footer.width
                enabled: !editor.controller.busy
                onClicked: editor.keepDraft()
            }

            DButton {
                id: discardButton
                text: "Discard"
                danger: true
                variant: "tonal"
                maximumWidth: footer.width
                enabled: !editor.controller.busy
                onClicked: editor.controller.discard()
            }
        }
    }
}
