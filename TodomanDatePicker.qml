import QtQuick
import QtQuick.Controls
import qs.Common
import qs.DCommon.Widgets

Column {
    id: picker
    property string label: "Date"
    property var value: null
    property var controller
    property string fieldName: "due"
    property bool expanded: false
    property date month: new Date(new Date().getFullYear(), new Date().getMonth(), 1)
    readonly property var raw: controller.dateInputs[fieldName] || null
    readonly property string dateText: raw ? raw.date : value ? value.value.slice(0, 10) : ""
    readonly property string timeText: raw ? raw.time : value && value.kind === "datetime" ? value.value.slice(11, 16) : "09:00"
    readonly property int selectedMode: raw ? raw.mode : !value ? 0 : value.kind === "date" ? 1 : 2
    signal edited(var value)
    spacing: 4
    function pad(n) { return (n < 10 ? "0" : "") + n }
    function iso(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }
    function change(mode, date, time) {
        var state = {mode:mode, date:date, time:time, valid:false}
        var copy = Object.assign({}, controller.dateInputs); copy[fieldName] = state; controller.dateInputs = copy
        if (!mode) { state.valid = true; controller.dateInputs = Object.assign({}, copy); edited(null); return }
        var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date)
        if (!m) return
        var d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
        if (iso(d) !== date) return
        if (mode === 1) { state.valid = true; controller.dateInputs = Object.assign({}, copy); edited({kind:"date", value:date}); return }
        var t = /^(\d{2}):(\d{2})$/.exec(time)
        if (!t || Number(t[1]) > 23 || Number(t[2]) > 59) return
        d.setHours(Number(t[1]), Number(t[2]), 0, 0)
        if (d.getHours() !== Number(t[1]) || d.getMinutes() !== Number(t[2])) return
        var offset = -d.getTimezoneOffset(), sign = offset < 0 ? "-" : "+"; offset = Math.abs(offset)
        state.valid = true; controller.dateInputs = Object.assign({}, copy)
        edited({kind:"datetime", value:date + "T" + time + ":00" + sign + pad(Math.floor(offset / 60)) + ":" + pad(offset % 60)})
    }
    StyledText { text: picker.label; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeMedium }
    Row {
        width: parent.width; spacing: 4
        TodomanCombo { id: mode; width: 120; model: ["None", "Date", "Date & time"]; currentIndex: picker.selectedMode; onActivated: index => { var d = picker.dateText || picker.iso(new Date()); picker.change(index, d, picker.timeText) } }
        TodomanField { width: Math.max(0, parent.width - mode.width - 4); enabled: picker.selectedMode > 0; placeholderText: "YYYY-MM-DD"; text: picker.dateText; onTextEdited: if (inputFocused) picker.change(picker.selectedMode, text, picker.timeText); Accessible.name: picker.label + " date" }
    }
    TodomanField { width: parent.width; visible: picker.selectedMode === 2; placeholderText: "HH:mm (local time)"; text: picker.timeText; onTextEdited: if (inputFocused) picker.change(picker.selectedMode, picker.dateText, text); Accessible.name: picker.label + " local time" }
    Flow {
        width: parent.width; spacing: 4; visible: picker.selectedMode > 0
        TodomanButton { text: "Today"; onClicked: picker.change(picker.selectedMode, picker.iso(new Date()), picker.timeText) }
        TodomanButton { text: "Tomorrow"; onClicked: { var d = new Date(); d.setDate(d.getDate() + 1); picker.change(picker.selectedMode, picker.iso(d), picker.timeText) } }
        TodomanButton { text: picker.expanded ? "Hide calendar" : "Calendar"; onClicked: { if (!picker.expanded && picker.dateText) { var d = new Date(picker.dateText + "T12:00:00"); if (!isNaN(d.getTime())) picker.month = new Date(d.getFullYear(), d.getMonth(), 1) } picker.expanded = !picker.expanded } }
    }
    Column {
        width: parent.width; visible: picker.expanded && picker.selectedMode > 0; spacing: 3
        Row {
            width: parent.width
            TodomanButton { width: 45; text: "‹"; Accessible.name: "Previous month"; onClicked: picker.month = new Date(picker.month.getFullYear(), picker.month.getMonth() - 1, 1) }
            StyledText { width: parent.width - 90; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter; text: Qt.formatDate(picker.month, "MMMM yyyy"); color: Theme.surfaceText }
            TodomanButton { width: 45; text: "›"; Accessible.name: "Next month"; onClicked: picker.month = new Date(picker.month.getFullYear(), picker.month.getMonth() + 1, 1) }
        }
        Grid {
            width: parent.width; columns: 7
            Repeater { model: ["M", "T", "W", "T", "F", "S", "S"]; delegate: StyledText { required property string modelData; width: picker.width / 7; horizontalAlignment: Text.AlignHCenter; text: modelData; color: Theme.surfaceVariantText } }
            Repeater {
                model: 42
                delegate: TodomanButton {
                    required property int index
                    readonly property date day: new Date(picker.month.getFullYear(), picker.month.getMonth(), 1 + index - ((picker.month.getDay() + 6) % 7))
                    highlighted: picker.dateText === picker.iso(day)
                    width: picker.width / 7; implicitHeight: 32; text: day.getDate(); opacity: day.getMonth() === picker.month.getMonth() ? 1 : 0.5
                    Accessible.name: Qt.formatDate(day, "yyyy-MM-dd")
                    onClicked: { picker.change(picker.selectedMode, picker.iso(day), picker.timeText); picker.month = new Date(day.getFullYear(), day.getMonth(), 1); picker.expanded = false }
                }
            }
        }
    }
}
