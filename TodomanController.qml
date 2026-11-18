import QtQuick
import Quickshell.Io

Item {
    id: controller
    property string pythonExecutable: "python3"
    property string watchedLists: ""
    property string sortField: "due"
    property string defaultList: ""
    property bool showCompleted: false
    property var tasks: []
    property var lists: []
    property var unsupported: []
    property string viewList: ""
    property string viewStatus: "open"
    property string search: ""
    property string category: ""
    property string priorityFilter: ""
    property real clock: Date.now()
    property bool busy: false
    property bool loading: true
    property string snapshotError: ""
    property string operationError: ""
    readonly property string error: operationError || snapshotError
    readonly property string errorSource: operationError ? "operation" : snapshotError ? "snapshot" : ""
    property var activeRequest: null
    property bool refreshPending: false
    property bool recoverySnapshot: false
    property var draft: null
    property var draftBaseline: null
    property var identity: null
    property bool unknownOutcome: false
    property bool confirmDiscard: false
    property bool confirmDelete: false
    property int editorSession: 0
    property bool ready: false
    property var dateInputs: ({})
    readonly property bool invalidDates: Object.keys(dateInputs).some(function(k) { return !dateInputs[k].valid })
    readonly property bool editing: draft !== null
    readonly property bool dirty: editing && (invalidDates || JSON.stringify(draft) !== JSON.stringify(draftBaseline))
    readonly property int openCount: tasks.filter(function(t) { return controller.isOpen(t) }).length
    readonly property string countText: String(openCount) + (unsupported.length ? "+" : "")
    readonly property var viewLists: lists.filter(function(name) { var w = controller.watched().map(function(s) { return s.toLowerCase() }); return !w.length || w.indexOf(name.toLowerCase()) >= 0 })
    readonly property var visibleTasks: filteredTasks()
    readonly property var groups: groupTasks()
    readonly property var nearest: nearestTask()
    signal requestFinished()

    function clone(value) { return JSON.parse(JSON.stringify(value)) }
    function setError(message, source) { if (source === "snapshot") snapshotError = message; else operationError = message }
    function clearError() { operationError = "" }
    function isOpen(task) { return !task.completed && task.status !== "COMPLETED" && task.status !== "CANCELLED" }
    function watched() { return watchedLists.split(",").map(function(s) { return s.trim() }).filter(function(s) { return s.length > 0 }) }
    function dueTime(value) {
        if (!value) return NaN
        if (value.kind === "date") {
            var p = value.value.split("-")
            return new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]) + 1).getTime() - 1
        }
        return new Date(value.value).getTime()
    }
    function overdue(task) { return isOpen(task) && task.due && dueTime(task.due) < clock }
    function filteredTasks() {
        var needle = search.toLowerCase().trim()
        return tasks.filter(function(t) {
            if (viewList && t.list !== viewList) return false
            if (viewStatus === "open" && !isOpen(t)) return false
            if (viewStatus !== "open" && viewStatus !== "all" && t.status !== viewStatus) return false
            if (category && (t.categories || []).indexOf(category) < 0) return false
            if (priorityFilter !== "" && String(t.priority) !== priorityFilter) return false
            return !needle || [t.summary, t.description, t.location, t.list, (t.categories || []).join(" ")].join(" ").toLowerCase().indexOf(needle) >= 0
        })
    }
    function groupTasks() {
        var tick = clock
        var buckets = {overdue: [], today: [], upcoming: [], none: [], closed: []}
        var today = new Date(tick).toDateString()
        visibleTasks.forEach(function(t) {
            var key = !isOpen(t) ? "closed" : !t.due ? "none" : overdue(t) ? "overdue" : new Date(dueTime(t.due)).toDateString() === today ? "today" : "upcoming"
            buckets[key].push(t)
        })
        return [{key:"overdue", label:"Overdue"}, {key:"today", label:"Today"}, {key:"upcoming", label:"Upcoming"}, {key:"none", label:"No due date"}, {key:"closed", label:"Completed and cancelled"}].filter(function(g) { g.tasks = buckets[g.key]; return g.tasks.length })
    }
    function nearestTask() {
        var now = clock, future = null, past = null
        tasks.forEach(function(t) {
            if (!isOpen(t) || !t.due) return
            var n = dueTime(t.due)
            if (!isFinite(n)) return
            if (n >= now && (!future || n < dueTime(future.due))) future = t
            if (n < now && (!past || n > dueTime(past.due))) past = t
        })
        return future || past
    }
    function countdown(task, shortForm) {
        if (!task) return ""
        var m = Math.ceil((dueTime(task.due) - clock) / 60000)
        if (m <= 0) return shortForm ? "!" : "overdue"
        if (m < 60) return m + "m"
        if (m < 1440) return Math.floor(m / 60) + "h" + (shortForm ? "" : " " + (m % 60) + "m")
        return Math.floor(Math.ceil(m / 60) / 24) + "d" + (shortForm ? "" : " " + (Math.ceil(m / 60) % 24) + "h")
    }
    function refresh(explicitRetry) {
        if (busy) { refreshPending = true; return }
        recoverySnapshot = explicitRetry === true && unknownOutcome && !editing
        if (recoverySnapshot) clearError()
        send({action:"snapshot", lists:watched(), sort:sortField})
    }
    function send(request) {
        if (busy) return
        busy = true; if (request.action !== "snapshot") clearError(); activeRequest = request
        process.output = ""; process.diagnostic = ""
        process.command = [pythonExecutable || "python3", decodeURIComponent(Qt.resolvedUrl("todoman_backend.py").toString().replace(/^file:\/\//, ""))]
        process.stdinEnabled = true
        process.running = true
    }
    function openNew() {
        if (busy || editing || unknownOutcome) return
        identity = null; clearError(); editorSession++
        draft = {summary:"", list:viewList || defaultList || "", description:"", location:"", categories:[], priority:0, status:"NEEDS-ACTION", percent:0, start:null, due:null, rrule:""}
        draftBaseline = clone(draft)
    }
    function openTask(task) { if (!busy && !editing && !unknownOutcome) send({action:"detail", id:task.id, uid:task.uid}) }
    function setField(name, value) {
        var copy = clone(draft); copy[name] = value
        if (name === "status" && value === "COMPLETED") copy.percent = 100
        if (name === "status" && value !== "COMPLETED" && copy.percent === 100) copy.percent = 0
        if (name === "percent" && value === 100) copy.status = "COMPLETED"
        if (name === "percent" && value < 100 && copy.status === "COMPLETED") copy.status = value ? "IN-PROCESS" : "NEEDS-ACTION"
        draft = copy
    }
    function leave() { if (busy) return; if (dirty || unknownOutcome) confirmDiscard = true; else discard() }
    function discard() { draft = null; draftBaseline = null; identity = null; dateInputs = ({}); confirmDiscard = false; confirmDelete = false; clearError() }
    function save() {
        if (busy || unknownOutcome || !draft) return
        if (invalidDates) { setError("Enter a valid date and time before saving.", "operation"); return }
        var changes = {}, keys = Object.keys(draft)
        for (var i = 0; i < keys.length; i++) if (!identity || JSON.stringify(draft[keys[i]]) !== JSON.stringify(draftBaseline[keys[i]])) changes[keys[i]] = draft[keys[i]]
        if (identity && !Object.keys(changes).length) { discard(); return }
        if (!draft.summary.trim()) { setError("Enter a task summary.", "operation"); return }
        if (!identity && !changes.list) delete changes.list
        var request = identity ? {action:"save", id:identity.id, uid:identity.uid, revision:identity.revision, changes:changes} : {action:"create", changes:changes}
        send(request)
    }
    function action(name, task, target) {
        if (busy || unknownOutcome || !task) return
        var request = {action:name, id:task.id, uid:task.uid, revision:task.revision}
        if (name === "move" || name === "copy") request.target_list = target
        send(request)
    }
    function adopt(task) { identity = {id:task.id, uid:task.uid, revision:task.revision} }
    function validTask(t) {
        return t && Number.isInteger(t.id) && typeof t.uid === "string" && !!t.uid && typeof t.revision === "string" && !!t.revision && typeof t.summary === "string" && typeof t.list === "string" && Array.isArray(t.categories) && typeof t.status === "string" && typeof t.completed === "boolean" && typeof t.recurring === "boolean" && typeof t.priority === "number" && typeof t.percent === "number" && validDate(t.start) && validDate(t.due)
    }
    function validDate(d) { return d === null || (d && (d.kind === "date" || d.kind === "datetime") && typeof d.value === "string" && !!d.value) }
    function finish(code, output) {
        var request = activeRequest, result = null
        if (!request) return
        try { result = JSON.parse(output.trim()) } catch (e) {}
        busy = false; activeRequest = null; loading = false
        if (code !== 0 && result && result.ok) result = null
        if (!result || typeof result.ok !== "boolean") {
            setError("The task helper did not return a valid response.", request.action === "snapshot" ? "snapshot" : "operation")
            if (request.action !== "snapshot" && request.action !== "detail") unknownOutcome = true
        } else if (!result.ok) {
            setError(result.message || "The task operation failed.", request.action === "snapshot" ? "snapshot" : "operation")
            if (result.mutated && validTask(result.task)) {
                adopt(result.task)
                if (draft && request.action === "create" && !draft.list) { var updated = clone(draft); updated.list = result.task.list; draft = updated }
                if (draft) draftBaseline = fields(result.task)
            } else if (result.mutated || result.code === "partial") unknownOutcome = true
            if (result.mutated) refreshPending = true
        } else if (request.action === "snapshot") {
            if (Array.isArray(result.tasks) && result.tasks.every(validTask) && Array.isArray(result.lists) && result.lists.every(function(s) { return typeof s === "string" }) && (result.unsupported === undefined || (Array.isArray(result.unsupported) && result.unsupported.every(function(entry) { return entry && typeof entry.message === "string" })))) {
                tasks = result.tasks; lists = result.lists; unsupported = result.unsupported || []
                if (viewList && viewLists.indexOf(viewList) < 0) viewList = ""
                snapshotError = ""
                if (recoverySnapshot && !unsupported.length) unknownOutcome = false
            }
            else setError("The task helper returned an incomplete snapshot.", "snapshot")
        } else if (request.action === "detail") {
            if (validTask(result.task) && result.task.id === request.id && result.task.uid === request.uid) { editorSession++; adopt(result.task); draft = fields(result.task); draftBaseline = clone(draft) }
            else setError("The task helper returned no task details.", "operation")
        } else {
            if ((request.action === "delete" && result.task === null) || (request.action !== "delete" && validTask(result.task) && (request.action === "create" || request.action === "copy" || result.task.uid === request.uid))) {
                if (request.action === "create" || request.action === "save" || request.action === "delete" || request.action === "copy") discard()
                else if (editing) { adopt(result.task); draft = fields(result.task); draftBaseline = clone(draft) }
                refreshPending = true
            } else { setError("The helper returned an invalid write result. Refresh and reopen before retrying.", "operation"); unknownOutcome = true; refreshPending = true }
        }
        requestFinished()
        if (refreshPending) { refreshPending = false; Qt.callLater(refresh) }
    }
    function fields(t) { return {summary:t.summary || "", list:t.list || "", description:t.description || "", location:t.location || "", categories:t.categories || [], priority:t.priority || 0, status:t.status || "NEEDS-ACTION", percent:t.percent || 0, start:t.start || null, due:t.due || null, rrule:t.rrule || ""} }
    Process {
        id: process
        property string output: ""
        property string diagnostic: ""
        stdout: SplitParser { onRead: data => { process.output += data + "\n" } }
        stderr: SplitParser { onRead: data => { process.diagnostic = (process.diagnostic + data + "\n").slice(-4096) } }
        onStarted: { write(JSON.stringify(controller.activeRequest)); stdinEnabled = false }
        onExited: (exitCode, exitStatus) => controller.finish(exitCode, output)
        onRunningChanged: if (!running && controller.busy && controller.activeRequest) { controller.setError("The task helper could not be started. Check the Python interpreter setting.", controller.activeRequest.action === "snapshot" ? "snapshot" : "operation"); controller.busy = false; controller.activeRequest = null; controller.loading = false; controller.requestFinished(); if (controller.refreshPending) { controller.refreshPending = false; Qt.callLater(controller.refresh) } }
    }
    Timer { interval: 60000; repeat: true; running: true; onTriggered: controller.clock = Date.now() }
    onWatchedListsChanged: if (ready) refresh()
    onSortFieldChanged: if (ready) refresh()
    onShowCompletedChanged: if (ready) viewStatus = showCompleted ? "all" : "open"
    Component.onCompleted: { viewStatus = showCompleted ? "all" : "open"; ready = true; refresh() }
}
