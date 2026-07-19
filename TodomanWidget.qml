// Todoman tasks as a DankBar pill + interactive popout.
// Backend: the `todo` CLI (todoman) with --porcelain JSON output.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root
    pluginId: "dankTodoman"

    // ── Settings (populated from pluginData by the base component) ───
    readonly property string listFilter: pluginData.listFilter || ""      // comma-separated list names, empty = all
    readonly property int refreshInterval: pluginData.refreshInterval || 5 // minutes
    readonly property bool showCompleted: pluginData.showCompleted === true
    readonly property string sortField: pluginData.sortField || "due"
    readonly property string defaultList: pluginData.defaultList || ""

    // ── Runtime state ───────────────────────────────────────────────
    property var tasks: []
    property int openCount: 0
    property var lists: []                 // ["work", "personal"]
    property bool isLoading: true
    property bool hasError: false
    property string errorText: ""

    // ── Draft state for the add/edit form (summary lives in the field itself) ─
    property string draftList: ""
    property bool draftDueEnabled: false
    property var draftDueDate: new Date()
    property bool draftAllDay: false
    property bool showDuePicker: false
    property string draftPriority: "none"      // none | low | medium | high

    // Edit mode: -1 = adding a new task, otherwise the id being edited.
    property int editingId: -1
    property var editingTask: null
    readonly property bool isEditing: editingId >= 0

    signal formReset()             // clears + refocuses the summary field
    signal prefillSummary(string s) // pushes text into the summary field (edit mode)

    // Max popout height before the content scrolls (grows to fit until this).
    // ~470 ≈ 6 tasks visible (7th scrolls) with the date picker closed.
    property int popoutMaxHeight: 470

    // Reusable +/- stepper button (declared at file scope; usable in the popout)
    component Stepper: Rectangle {
        property string glyph: ""
        signal act()
        width: 24; height: 30; radius: Theme.cornerRadius
        color: stepArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.12) : Theme.surfaceContainerHigh
        DankIcon { anchors.centerIn: parent; name: parent.glyph; size: 14; color: Theme.primary }
        MouseArea {
            id: stepArea
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: parent.act()
        }
    }

    // ── Internal process buffers ────────────────────────────────────
    property string _listBuf: ""
    property string _listsBuf: ""
    property string _addBuf: ""
    property string _saveBuf: ""

    // Absolute path to the bundled .ics editor, resolved next to this QML file.
    readonly property string _icsEditScript: Qt.resolvedUrl("ics_edit.py").toString().replace(/^file:\/\//, "")

    Component.onCompleted: {
        var d = new Date();
        d.setHours(18, 0, 0, 0);
        draftDueDate = d;
        fetchLists();
        fetchTasks();
    }

    Timer {
        interval: root.refreshInterval * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.fetchTasks()
    }

    // ── Date/time helpers ───────────────────────────────────────────
    function pad2(n) { return ("0" + n).slice(-2); }
    readonly property var _months: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    function fmtDueCmd(d, allDay) {
        var s = d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());
        if (!allDay) s += " " + pad2(d.getHours()) + ":" + pad2(d.getMinutes());
        return s;
    }

    function fmtDueChip(d, allDay) {
        var s = _months[d.getMonth()] + " " + d.getDate();
        if (!allDay) s += " " + pad2(d.getHours()) + ":" + pad2(d.getMinutes());
        return s;
    }

    function setDuePreset(which) {
        var d = new Date();
        d.setSeconds(0, 0);
        if (which === "today") d.setHours(18, 0);
        else if (which === "tomorrow") { d.setDate(d.getDate() + 1); d.setHours(18, 0); }
        else if (which === "nextweek") { d.setDate(d.getDate() + 7); d.setHours(18, 0); }
        draftDueDate = d;
        draftDueEnabled = true;
        draftAllDay = false;
    }

    function adjustDueTime(field, delta) {
        var d = new Date(draftDueDate);
        if (field === "h") d.setHours(d.getHours() + delta);
        else d.setMinutes(d.getMinutes() + delta);
        draftDueDate = d;
        draftDueEnabled = true;
    }

    // due is a unix timestamp in seconds (or null).
    function formatDue(ts) {
        if (!ts) return "";
        var d = new Date(ts * 1000);
        var now = new Date();
        var startToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        var dueDay = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
        var dayDiff = Math.round((dueDay - startToday) / 86400000);
        var label;
        if (dayDiff < 0) label = "overdue";
        else if (dayDiff === 0) label = "today";
        else if (dayDiff === 1) label = "tomorrow";
        else label = _months[d.getMonth()] + " " + d.getDate();
        if (d.getHours() !== 0 || d.getMinutes() !== 0)
            label += " " + pad2(d.getHours()) + ":" + pad2(d.getMinutes());
        return label;
    }

    function isOverdue(ts) { return ts ? (ts * 1000) < Date.now() : false; }

    // ── Due-based grouping ──────────────────────────────────────────
    // Tasks are split into fixed buckets by their due date; empty
    // buckets are dropped so only relevant sections render.
    readonly property var dueGroupOrder: [
        { key: "overdue",  label: "Overdue" },
        { key: "today",    label: "Due today" },
        { key: "tomorrow", label: "Due tomorrow" },
        { key: "upcoming", label: "Upcoming" },
        { key: "none",     label: "No due date" }
    ]

    function dueGroupKey(ts) {
        if (!ts) return "none";
        var now = new Date();
        var startToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        var d = new Date(ts * 1000);
        var dueDay = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
        var dayDiff = Math.round((dueDay - startToday) / 86400000);
        if (dayDiff < 0) return "overdue";
        if (dayDiff === 0) return "today";
        if (dayDiff === 1) return "tomorrow";
        return "upcoming";
    }

    // [{ label, tasks: [...] }] in dueGroupOrder, non-empty groups only.
    readonly property var groupedTasks: {
        var buckets = {};
        for (var i = 0; i < tasks.length; i++) {
            var k = dueGroupKey(tasks[i].due);
            (buckets[k] || (buckets[k] = [])).push(tasks[i]);
        }
        var out = [];
        for (var g = 0; g < dueGroupOrder.length; g++) {
            var def = dueGroupOrder[g];
            var items = buckets[def.key];
            if (items && items.length)
                out.push({ label: def.label, tasks: items });
        }
        return out;
    }

    // Priority: iCalendar 1 (highest) .. 9 (lowest), 0 = none.
    function priorityColor(p) {
        if (!p || p <= 0) return "transparent";
        if (p <= 4) return Theme.error;
        if (p === 5) return Theme.warning;
        return Theme.surfaceVariantText;
    }

    // ── Command builders ────────────────────────────────────────────
    function listArgs() {
        var args = [];
        if (listFilter) {
            var names = listFilter.split(",");
            for (var i = 0; i < names.length; i++) {
                var n = names[i].trim();
                if (n) args.push(n);
            }
        }
        return args;
    }

    function fetchTasks() {
        _listBuf = "";
        var cmd = ["todo", "--porcelain", "list", "--sort", sortField];
        if (showCompleted) { cmd.push("--status"); cmd.push("ANY"); }
        var la = listArgs();
        for (var i = 0; i < la.length; i++) cmd.push(la[i]);
        listProc.command = cmd;
        listProc.running = true;
    }

    function fetchLists() {
        _listsBuf = "";
        listsProc.command = ["todo", "--porcelain", "lists"];
        listsProc.running = true;
    }

    function addTask(summary) {
        summary = (summary || "").trim();
        if (!summary) return;
        var cmd = ["todo", "new"];
        var l = draftList || defaultList;
        if (l) { cmd.push("-l"); cmd.push(l); }
        if (draftDueEnabled && draftDueDate) {
            cmd.push("-d");
            cmd.push(fmtDueCmd(draftDueDate, draftAllDay));
        }
        if (draftPriority !== "none") { cmd.push("--priority"); cmd.push(draftPriority); }
        cmd.push(summary);
        _addBuf = "";
        addProc.command = cmd;
        addProc.running = true;
    }

    function markDone(id) {
        doneProc.command = ["todo", "done", String(id)];
        doneProc.running = true;
    }

    function deleteTask(id) {
        deleteProc.command = ["todo", "delete", "--yes", String(id)];
        deleteProc.running = true;
    }

    // Map a stored iCalendar priority number back to our word buckets.
    function priorityWord(p) {
        if (!p || p <= 0) return "none";
        if (p <= 4) return "high";
        if (p === 5) return "medium";
        return "low";
    }

    // Enter edit mode: prefill the shared form from an existing task.
    function openEdit(task) {
        editingId = task.id;
        editingTask = task;
        draftList = task.list || draftList;
        draftPriority = priorityWord(task.priority);
        if (task.due) {
            draftDueEnabled = true;
            draftDueDate = new Date(task.due * 1000);
            draftAllDay = (draftDueDate.getHours() === 0 && draftDueDate.getMinutes() === 0);
        } else {
            draftDueEnabled = false;
        }
        showDuePicker = false;
        prefillSummary(task.summary || "");
    }

    function cancelEdit() {
        editingId = -1;
        editingTask = null;
        draftDueEnabled = false;
        draftAllDay = false;
        draftPriority = "none";
        showDuePicker = false;
        formReset();
    }

    // Save edits. todoman's `edit` sets due/priority natively; summary and
    // field-clears are done by a small python pass over the .ics file.
    function saveEdit(summary) {
        summary = (summary || "").trim();
        if (editingId < 0 || !summary || !editingTask) return;
        var id = editingId;
        var t = editingTask;
        var steps = [];

        // move between lists
        if (draftList && draftList !== t.list)
            steps.push(["todo", "move", String(id), draftList]);

        // native edit for due/priority we want to set
        var ea = ["todo", "edit", String(id)];
        var hasNative = false;
        if (draftDueEnabled && draftDueDate) { ea.push("-d"); ea.push(fmtDueCmd(draftDueDate, draftAllDay)); hasNative = true; }
        if (draftPriority !== "none") { ea.push("--priority"); ea.push(draftPriority); hasNative = true; }
        if (hasNative) steps.push(ea);

        // file pass: rename summary, clear due / priority when unset
        var clearDue = !draftDueEnabled && !!t.due;
        var clearPrio = draftPriority === "none" && t.priority > 0;
        var summaryChanged = summary !== (t.summary || "");
        if (summaryChanged || clearDue || clearPrio)
            steps.push(["python3", root._icsEditScript, String(id), summary,
                        clearDue ? "1" : "0", clearPrio ? "1" : "0"]);

        if (steps.length === 0) { cancelEdit(); return; }
        _saveSteps = steps;
        _saveIdx = 0;
        _runSaveStep();
    }

    property var _saveSteps: []
    property int _saveIdx: 0
    function _runSaveStep() {
        if (_saveIdx >= _saveSteps.length) {
            cancelEdit();
            fetchTasks();
            fetchLists();
            return;
        }
        saveProc.command = _saveSteps[_saveIdx];
        saveProc.running = true;
    }

    // ── Processes ───────────────────────────────────────────────────
    Process {
        id: listProc
        running: false
        stdout: SplitParser { onRead: data => { root._listBuf += data + "\n"; } }
        onExited: (exitCode) => {
            root.isLoading = false;
            if (exitCode !== 0) {
                root.hasError = true;
                root.errorText = "todo exited with code " + exitCode;
                return;
            }
            try {
                var arr = JSON.parse(root._listBuf.trim() || "[]");
                var open = 0;
                for (var i = 0; i < arr.length; i++) if (!arr[i].completed) open++;
                root.tasks = arr;
                root.openCount = open;
                root.hasError = false;
            } catch (e) {
                root.hasError = true;
                root.errorText = "Failed to parse todo output: " + e;
            }
        }
    }

    Process {
        id: listsProc
        running: false
        stdout: SplitParser { onRead: data => { root._listsBuf += data + "\n"; } }
        onExited: (exitCode) => {
            if (exitCode !== 0) return;
            try {
                var arr = JSON.parse(root._listsBuf.trim() || "[]");
                root.lists = arr;
                if (!root.draftList && arr.length > 0)
                    root.draftList = (root.defaultList && arr.indexOf(root.defaultList) >= 0)
                        ? root.defaultList : arr[0];
            } catch (e) {}
        }
    }

    Process {
        id: addProc
        running: false
        stdout: SplitParser { onRead: data => { root._addBuf += data + "\n"; } }
        stderr: SplitParser { onRead: data => { root._addBuf += data + "\n"; } }
        onExited: (exitCode) => {
            if (exitCode === 0) {
                root.draftDueEnabled = false;
                root.draftAllDay = false;
                root.draftPriority = "none";
                root.showDuePicker = false;
                root.formReset();
                root.fetchTasks();
            } else {
                ToastService.showError("todoman", root._addBuf.trim() || "Failed to create task");
            }
        }
    }

    // Runs each step of an edit save in sequence (move / edit / .ics pass).
    Process {
        id: saveProc
        running: false
        stdout: SplitParser { onRead: data => { root._saveBuf += data + "\n"; } }
        stderr: SplitParser { onRead: data => { root._saveBuf += data + "\n"; } }
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                ToastService.showError("todoman", root._saveBuf.trim() || "Failed to save changes");
                root.cancelEdit();
                root.fetchTasks();
                return;
            }
            root._saveBuf = "";
            root._saveIdx += 1;
            root._runSaveStep();
        }
    }

    Process {
        id: deleteProc
        running: false
        onExited: (exitCode) => {
            if (exitCode === 0) root.fetchTasks();
            else ToastService.showError("todoman", "Failed to delete task");
        }
    }

    Process {
        id: doneProc
        running: false
        onExited: (exitCode) => {
            if (exitCode === 0) {
                refetchDelay.restart();     // let the checkmark linger before the row leaves
            } else {
                ToastService.showError("todoman", "Failed to complete task");
                root.fetchTasks();          // reset the optimistic checkmark
            }
        }
    }

    // Brief pause after `todo done` so the completed row shows its checkmark first.
    Timer {
        id: refetchDelay
        interval: 550
        repeat: false
        onTriggered: root.fetchTasks()
    }

    // ── Bar pill (horizontal) ───────────────────────────────────────
    horizontalBarPill: Component {
        StyledRect {
            implicitWidth: pillRow.implicitWidth + Theme.spacingM * 2
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                DankIcon {
                    name: "checklist"
                    size: root.iconSize
                    color: root.openCount > 0 ? Theme.surfaceText : Theme.surfaceTextMedium
                    anchors.verticalCenter: parent.verticalCenter
                }
                StyledText {
                    visible: root.openCount > 0
                    text: root.openCount
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // ── Bar pill (vertical bar layout) ──────────────────────────────
    verticalBarPill: Component {
        StyledRect {
            width: parent.widgetThickness
            implicitHeight: pillCol.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Column {
                id: pillCol
                anchors.centerIn: parent
                spacing: 1
                DankIcon {
                    name: "checklist"
                    size: root.iconSize
                    color: root.openCount > 0 ? Theme.surfaceText : Theme.surfaceTextMedium
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                StyledText {
                    visible: root.openCount > 0
                    text: root.openCount
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    // ── Popout ──────────────────────────────────────────────────────
    popoutWidth: 400
    popoutHeight: 500
    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: "Tasks"
            detailsText: root.openCount + (root.openCount === 1 ? " open task" : " open tasks")
            showCloseButton: true
            closePopout: function () { root.closePopout() }

            // Refresh button in the header
            headerActions: Component {
                DankActionButton {
                    iconName: "refresh"
                    iconColor: Theme.surfaceVariantText
                    buttonSize: 30
                    tooltipText: "Refresh"
                    onClicked: { root.fetchTasks(); root.fetchLists(); }
                }
            }

            // Refetch every time the popout is opened
            Connections {
                target: popout.parentPopout
                ignoreUnknownSignals: true
                function onShouldBeVisibleChanged() {
                    if (popout.parentPopout && popout.parentPopout.shouldBeVisible)
                        root.fetchTasks();
                }
            }

            // Sync the summary field with add/edit form state
            Connections {
                target: root
                function onFormReset() { summaryField.text = ""; }
                function onPrefillSummary(s) { summaryField.text = s; flick.contentY = 0; }
            }

            // Whole popout scrolls as one flickable (khal pattern)
            DankFlickable {
                id: flick
                width: parent.width
                implicitHeight: Math.min(contentHeight, root.popoutMaxHeight)
                contentHeight: col.implicitHeight
                clip: true

                Column {
                    id: col
                    width: flick.width
                    spacing: Theme.spacingM

                    // ── Add-task card ──────────────────────────────
                    StyledRect {
                        width: parent.width
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainer
                        implicitHeight: addCol.implicitHeight + Theme.spacingM * 2

                        Column {
                            id: addCol
                            anchors.fill: parent
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingS

                            // edit-mode banner
                            Row {
                                width: parent.width
                                visible: root.isEditing
                                spacing: Theme.spacingS
                                StyledText {
                                    width: parent.width - cancelEditBtn.width - Theme.spacingS
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Editing task"
                                    color: Theme.primary
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                                DankActionButton {
                                    id: cancelEditBtn
                                    anchors.verticalCenter: parent.verticalCenter
                                    iconName: "close"
                                    iconSize: 16
                                    buttonSize: 28
                                    tooltipText: "Cancel edit"
                                    onClicked: root.cancelEdit()
                                }
                            }

                            // summary + add/save button
                            Row {
                                width: parent.width
                                spacing: Theme.spacingS

                                DankTextField {
                                    id: summaryField
                                    width: parent.width - addBtn.width - Theme.spacingS
                                    placeholderText: root.isEditing ? "Task summary…" : "New task…"
                                    leftIconName: root.isEditing ? "edit" : "add_task"
                                    onAccepted: root.isEditing ? root.saveEdit(text) : root.addTask(text)
                                }
                                DankActionButton {
                                    id: addBtn
                                    anchors.verticalCenter: parent.verticalCenter
                                    iconName: root.isEditing ? "check" : "add"
                                    iconColor: Theme.primary
                                    buttonSize: 36
                                    tooltipText: root.isEditing ? "Save" : "Add task"
                                    enabled: summaryField.text.trim().length > 0
                                    onClicked: root.isEditing ? root.saveEdit(summaryField.text) : root.addTask(summaryField.text)
                                }
                            }

                            // list dropdown + due chip
                            Row {
                                width: parent.width
                                spacing: Theme.spacingS

                                DankDropdown {
                                    id: listDrop
                                    visible: root.lists.length > 0
                                    dropdownWidth: 130
                                    currentValue: root.draftList
                                    options: root.lists
                                    onValueChanged: value => root.draftList = value
                                }

                                StyledRect {
                                    id: dueChip
                                    height: 38
                                    width: parent.width - (listDrop.visible ? listDrop.width + Theme.spacingS : 0)
                                    radius: Theme.cornerRadius
                                    color: dueChipArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                                    border.width: root.showDuePicker ? 1 : 0
                                    border.color: Theme.primary

                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: Theme.spacingM
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.spacingS
                                        DankIcon {
                                            name: "event"
                                            size: 16
                                            color: root.draftDueEnabled ? Theme.primary : Theme.surfaceVariantText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        StyledText {
                                            text: root.draftDueEnabled ? root.fmtDueChip(root.draftDueDate, root.draftAllDay) : "Add due date"
                                            color: root.draftDueEnabled ? Theme.surfaceText : Theme.surfaceVariantText
                                            font.pixelSize: Theme.fontSizeSmall
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    DankActionButton {
                                        visible: root.draftDueEnabled
                                        anchors.right: parent.right
                                        anchors.rightMargin: Theme.spacingXS
                                        anchors.verticalCenter: parent.verticalCenter
                                        iconName: "close"
                                        iconSize: 14
                                        buttonSize: 24
                                        tooltipText: "Clear due date"
                                        onClicked: { root.draftDueEnabled = false; root.showDuePicker = false; }
                                    }

                                    MouseArea {
                                        id: dueChipArea
                                        anchors.fill: parent
                                        anchors.rightMargin: root.draftDueEnabled ? 28 : 0
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.showDuePicker = !root.showDuePicker
                                    }
                                }
                            }

                            // priority selector
                            Row {
                                width: parent.width
                                spacing: Theme.spacingS
                                StyledText {
                                    text: "Priority"
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Row {
                                    spacing: Theme.spacingXS
                                    anchors.verticalCenter: parent.verticalCenter
                                    Repeater {
                                        model: [
                                            {label: "None", key: "none", col: Theme.surfaceVariantText},
                                            {label: "Low", key: "low", col: Theme.surfaceVariantText},
                                            {label: "Med", key: "medium", col: Theme.warning},
                                            {label: "High", key: "high", col: Theme.error}
                                        ]
                                        delegate: StyledRect {
                                            required property var modelData
                                            readonly property bool sel: root.draftPriority === modelData.key
                                            height: 28
                                            width: prioLabel.implicitWidth + Theme.spacingM * 2
                                            radius: Theme.cornerRadius
                                            color: sel ? Theme.withAlpha(Theme.primary, 0.2)
                                                   : prioArea.containsMouse ? Theme.surfaceContainerHighest
                                                   : Theme.surfaceContainerHigh
                                            StyledText {
                                                id: prioLabel
                                                anchors.centerIn: parent
                                                text: modelData.label
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: sel ? Theme.primary : modelData.col
                                            }
                                            MouseArea {
                                                id: prioArea
                                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: root.draftPriority = modelData.key
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Expandable date/time picker ────────
                            Column {
                                width: parent.width
                                spacing: Theme.spacingS
                                visible: root.showDuePicker

                                // quick presets
                                Row {
                                    width: parent.width
                                    spacing: Theme.spacingXS
                                    Repeater {
                                        model: [
                                            {label: "Today", key: "today"},
                                            {label: "Tomorrow", key: "tomorrow"},
                                            {label: "Next week", key: "nextweek"}
                                        ]
                                        delegate: StyledRect {
                                            required property var modelData
                                            width: (parent.width - Theme.spacingXS * 2) / 3
                                            height: 28
                                            radius: Theme.cornerRadius
                                            color: presetArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.16) : Theme.surfaceContainerHigh
                                            StyledText {
                                                anchors.centerIn: parent
                                                text: modelData.label
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: Theme.surfaceText
                                            }
                                            MouseArea {
                                                id: presetArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.setDuePreset(modelData.key)
                                            }
                                        }
                                    }
                                }

                                // month header
                                Row {
                                    width: parent.width
                                    height: 28
                                    Rectangle {
                                        width: 28; height: 28; radius: Theme.cornerRadius
                                        color: prevArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.12) : "transparent"
                                        DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 16; color: Theme.primary }
                                        MouseArea {
                                            id: prevArea
                                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: { var d = new Date(root.draftDueDate); d.setMonth(d.getMonth() - 1); root.draftDueDate = d; }
                                        }
                                    }
                                    StyledText {
                                        width: parent.width - 56; height: 28
                                        text: root.draftDueDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")
                                        font.pixelSize: Theme.fontSizeMedium; font.weight: Font.Medium
                                        color: Theme.surfaceText
                                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                    }
                                    Rectangle {
                                        width: 28; height: 28; radius: Theme.cornerRadius
                                        color: nextArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.12) : "transparent"
                                        DankIcon { anchors.centerIn: parent; name: "chevron_right"; size: 16; color: Theme.primary }
                                        MouseArea {
                                            id: nextArea
                                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: { var d = new Date(root.draftDueDate); d.setMonth(d.getMonth() + 1); root.draftDueDate = d; }
                                        }
                                    }
                                }

                                // weekday headers
                                Row {
                                    width: parent.width
                                    Repeater {
                                        model: {
                                            var days = [], loc = Qt.locale(), qtFirst = loc.firstDayOfWeek;
                                            for (var i = 0; i < 7; ++i)
                                                days.push(loc.dayName(((qtFirst - 1 + i) % 7) + 1, Locale.ShortFormat).slice(0, 2));
                                            return days;
                                        }
                                        delegate: Item {
                                            width: parent.width / 7; height: 18
                                            StyledText {
                                                anchors.centerIn: parent; text: modelData
                                                font.pixelSize: 10; font.weight: Font.Medium
                                                color: Theme.withAlpha(Theme.surfaceText, 0.6)
                                            }
                                        }
                                    }
                                }

                                // 6x7 day grid
                                Grid {
                                    id: dayGrid
                                    width: parent.width
                                    columns: 7; rows: 6
                                    property int displayMonth: root.draftDueDate.getMonth()
                                    property var firstDay: {
                                        var firstOfMonth = new Date(root.draftDueDate.getFullYear(), root.draftDueDate.getMonth(), 1);
                                        var loc = Qt.locale(), jsFirst = loc.firstDayOfWeek % 7;
                                        var diff = (firstOfMonth.getDay() - jsFirst + 7) % 7;
                                        var d = new Date(firstOfMonth); d.setDate(d.getDate() - diff);
                                        return d;
                                    }
                                    Repeater {
                                        model: 42
                                        delegate: Item {
                                            required property int index
                                            property var dayDate: {
                                                var d = new Date(dayGrid.firstDay); d.setDate(d.getDate() + index); return d;
                                            }
                                            property bool isCurrentMonth: dayDate.getMonth() === dayGrid.displayMonth
                                            property bool isToday: dayDate.toDateString() === new Date().toDateString()
                                            property bool isSelected: root.draftDueEnabled && dayDate.toDateString() === root.draftDueDate.toDateString()
                                            width: dayGrid.width / 7; height: 28
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 24; height: 24; radius: 12
                                                color: parent.isSelected ? Theme.primary
                                                       : parent.isToday ? Theme.withAlpha(Theme.primary, 0.12)
                                                       : dayArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.08)
                                                       : "transparent"
                                                StyledText {
                                                    anchors.centerIn: parent
                                                    text: parent.parent.dayDate.getDate()
                                                    font.pixelSize: 11
                                                    font.weight: (parent.parent.isToday || parent.parent.isSelected) ? Font.Medium : Font.Normal
                                                    color: parent.parent.isSelected ? Theme.onPrimary
                                                           : parent.parent.isToday ? Theme.primary
                                                           : parent.parent.isCurrentMonth ? Theme.surfaceText
                                                           : Theme.withAlpha(Theme.surfaceText, 0.35)
                                                }
                                            }
                                            MouseArea {
                                                id: dayArea
                                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    var d = new Date(parent.dayDate);
                                                    d.setHours(root.draftDueDate.getHours(), root.draftDueDate.getMinutes(), 0, 0);
                                                    root.draftDueDate = d;
                                                    root.draftDueEnabled = true;
                                                }
                                            }
                                        }
                                    }
                                }

                                // all-day toggle + time steppers
                                Row {
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    StyledRect {
                                        height: 30
                                        width: allDayLabel.implicitWidth + Theme.spacingM * 2
                                        radius: Theme.cornerRadius
                                        color: root.draftAllDay ? Theme.withAlpha(Theme.primary, 0.2) : Theme.surfaceContainerHigh
                                        anchors.verticalCenter: parent.verticalCenter
                                        StyledText {
                                            id: allDayLabel
                                            anchors.centerIn: parent
                                            text: "All day"
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: root.draftAllDay ? Theme.primary : Theme.surfaceVariantText
                                        }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: { root.draftAllDay = !root.draftAllDay; root.draftDueEnabled = true; }
                                        }
                                    }

                                    // time HH : MM steppers
                                    Row {
                                        visible: !root.draftAllDay
                                        spacing: 2
                                        anchors.verticalCenter: parent.verticalCenter

                                        Stepper { glyph: "remove"; onAct: root.adjustDueTime("h", -1) }
                                        StyledText {
                                            width: 26; height: 30
                                            text: root.pad2(root.draftDueDate.getHours())
                                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                            font.pixelSize: Theme.fontSizeMedium; color: Theme.surfaceText
                                        }
                                        Stepper { glyph: "add"; onAct: root.adjustDueTime("h", 1) }
                                        StyledText { width: 8; height: 30; text: ":"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; color: Theme.surfaceText }
                                        Stepper { glyph: "remove"; onAct: root.adjustDueTime("m", -5) }
                                        StyledText {
                                            width: 26; height: 30
                                            text: root.pad2(root.draftDueDate.getMinutes())
                                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                            font.pixelSize: Theme.fontSizeMedium; color: Theme.surfaceText
                                        }
                                        Stepper { glyph: "add"; onAct: root.adjustDueTime("m", 5) }
                                    }
                                }
                            }
                        }
                    }

                    // ── Empty / error / loading state ──────────────
                    StyledText {
                        width: parent.width
                        visible: root.tasks.length === 0
                        text: root.hasError ? root.errorText
                              : root.isLoading ? "Loading tasks…"
                              : "No tasks. Add one above ✨"
                        wrapMode: Text.WordWrap
                        color: root.hasError ? Theme.error : Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    // ── Task list (grouped by due date) ────────────
                    Column {
                        width: parent.width
                        spacing: Theme.spacingS

                        Repeater {
                            model: root.groupedTasks
                            delegate: Column {
                                id: groupCol
                                required property var modelData
                                width: parent.width
                                spacing: Theme.spacingXS

                                StyledText {
                                    width: parent.width
                                    text: groupCol.modelData.label + "  ·  " + groupCol.modelData.tasks.length
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.DemiBold
                                }

                                Repeater {
                                    model: groupCol.modelData.tasks
                                    delegate: StyledRect {
                                        id: taskDelegate
                                required property var modelData
                                property bool completing: false   // optimistic "just ticked" state
                                property bool confirmingDelete: false
                                readonly property bool done: modelData.completed || completing
                                width: parent.width
                                radius: Theme.cornerRadius
                                color: taskHover.hovered ? Theme.surfaceContainerHigh : Theme.surfaceContainer
                                implicitHeight: taskRow.implicitHeight + Theme.spacingS * 2
                                opacity: completing ? 0.5 : 1
                                Behavior on opacity {
                                    NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing }
                                }

                                HoverHandler { id: taskHover }

                                Row {
                                    id: taskRow
                                    visible: !taskDelegate.confirmingDelete
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Theme.spacingS
                                    anchors.rightMargin: Theme.spacingS + 64   // room for hover actions
                                    spacing: Theme.spacingS

                                    DankActionButton {
                                        anchors.verticalCenter: parent.verticalCenter
                                        iconName: taskDelegate.done ? "check_circle" : "radio_button_unchecked"
                                        iconColor: taskDelegate.done ? Theme.primary : Theme.surfaceVariantText
                                        buttonSize: 32
                                        tooltipText: taskDelegate.done ? "Completed" : "Mark done"
                                        enabled: !taskDelegate.done
                                        onClicked: {
                                            taskDelegate.completing = true;
                                            root.markDone(modelData.id);
                                        }
                                    }

                                    Rectangle {
                                        width: 6; height: 6; radius: 3
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: modelData.priority > 0
                                        color: root.priorityColor(modelData.priority)
                                    }

                                    Column {
                                        width: parent.width - 32 - Theme.spacingS * 2
                                               - (modelData.priority > 0 ? 6 + Theme.spacingS : 0)
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 1

                                        StyledText {
                                            width: parent.width
                                            text: modelData.summary || "(no summary)"
                                            color: taskDelegate.done ? Theme.surfaceVariantText : Theme.surfaceText
                                            font.pixelSize: Theme.fontSizeMedium
                                            font.strikeout: taskDelegate.done
                                            elide: Text.ElideRight
                                        }
                                        Row {
                                            spacing: Theme.spacingS
                                            visible: modelData.due || modelData.list
                                            StyledText {
                                                visible: !!modelData.due
                                                text: root.formatDue(modelData.due)
                                                color: root.isOverdue(modelData.due) && !modelData.completed ? Theme.error : Theme.surfaceVariantText
                                                font.pixelSize: Theme.fontSizeSmall
                                            }
                                            StyledText {
                                                visible: !!modelData.list
                                                text: "· " + modelData.list
                                                color: Theme.surfaceTextMedium
                                                font.pixelSize: Theme.fontSizeSmall
                                            }
                                        }
                                    }
                                }

                                // hover actions: edit + delete
                                Row {
                                    visible: taskHover.hovered && !taskDelegate.confirmingDelete && !taskDelegate.completing
                                    anchors.right: parent.right
                                    anchors.rightMargin: Theme.spacingS
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 0
                                    DankActionButton {
                                        iconName: "edit"
                                        iconSize: 16
                                        buttonSize: 28
                                        tooltipText: "Edit"
                                        onClicked: root.openEdit(taskDelegate.modelData)
                                    }
                                    DankActionButton {
                                        iconName: "delete"
                                        iconSize: 16
                                        buttonSize: 28
                                        iconColor: Theme.surfaceVariantText
                                        tooltipText: "Delete"
                                        onClicked: taskDelegate.confirmingDelete = true
                                    }
                                }

                                // delete confirmation bar
                                Row {
                                    visible: taskDelegate.confirmingDelete
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Theme.spacingM
                                    anchors.rightMargin: Theme.spacingS
                                    spacing: Theme.spacingS
                                    StyledText {
                                        width: parent.width - confirmDel.width - cancelDel.width - Theme.spacingS * 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Delete this task?"
                                        color: Theme.surfaceText
                                        font.pixelSize: Theme.fontSizeSmall
                                        elide: Text.ElideRight
                                    }
                                    DankActionButton {
                                        id: confirmDel
                                        anchors.verticalCenter: parent.verticalCenter
                                        iconName: "delete"
                                        iconSize: 16
                                        buttonSize: 30
                                        iconColor: Theme.error
                                        tooltipText: "Confirm delete"
                                        onClicked: {
                                            taskDelegate.confirmingDelete = false;
                                            root.deleteTask(taskDelegate.modelData.id);
                                        }
                                    }
                                    DankActionButton {
                                        id: cancelDel
                                        anchors.verticalCenter: parent.verticalCenter
                                        iconName: "close"
                                        iconSize: 16
                                        buttonSize: 30
                                        tooltipText: "Cancel"
                                        onClicked: taskDelegate.confirmingDelete = false
                                    }
                                }
                            }
                                    }   // Repeater over group.tasks
                                }       // group Column
                            }
                        }
                    }
                }
            }
        }
    }
