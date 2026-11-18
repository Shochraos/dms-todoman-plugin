import QtQuick
import QtQuick.Controls
import qs.Common
import qs.DCommon.Widgets

Column {
    id: recurrence
    property string value: ""
    property bool replacing: false
    property int session: 0
    onSessionChanged: replacing = false
    signal edited(string value)
    spacing: 4
    readonly property bool custom: value !== "" && !/^FREQ=(DAILY|WEEKLY|MONTHLY|YEARLY)(;INTERVAL=[1-9][0-9]*)?(;BYDAY=(MO|TU|WE|TH|FR|SA|SU)(,(MO|TU|WE|TH|FR|SA|SU))*)?$/.test(value)
    StyledText { text: "Repeat"; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeMedium }
    StyledText { width: parent.width; visible: recurrence.custom && !recurrence.replacing; text: "Custom repeat rule preserved. Replace it to edit repeat settings."; wrapMode: Text.Wrap; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall }
    TodomanButton { visible: recurrence.custom && !recurrence.replacing; text: "Replace custom repeat"; onClicked: recurrence.replacing = true }
    Column {
        width: parent.width; spacing: 4; visible: !recurrence.custom || recurrence.replacing
        TodomanCombo { id: frequency; width: parent.width; model: ["Does not repeat", "Daily", "Weekly", "Monthly", "Yearly"]; currentIndex: { var match = recurrence.value.match(/^FREQ=(DAILY|WEEKLY|MONTHLY|YEARLY)/); return match ? ["", "DAILY", "WEEKLY", "MONTHLY", "YEARLY"].indexOf(match[1]) : 0 } onActivated: index => recurrence.updateRule(index) }
        Row {
            visible: frequency.currentIndex > 0; spacing: 8
            StyledText { color: Theme.surfaceText; font.pixelSize: Theme.fontSizeSmall; text: "Every" }
            SpinBox { palette.text: Theme.surfaceText; palette.buttonText: Theme.surfaceText; palette.button: Theme.surfaceContainerHigh; palette.base: Theme.surfaceContainerHigh; palette.highlight: Theme.primary; id: interval; from: 1; to: 999; value: { var match = recurrence.value.match(/(?:^|;)INTERVAL=(\d+)/); return match ? Number(match[1]) : 1 } onValueModified: recurrence.updateRule(frequency.currentIndex) }
        }
        Flow {
            width: parent.width; spacing: 3; visible: frequency.currentIndex === 2
            Repeater { model: ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]; delegate: CheckBox { palette.windowText: Theme.surfaceText; palette.text: Theme.surfaceText; palette.button: Theme.surfaceContainerHigh; palette.highlight: Theme.primary; required property string modelData; text: modelData; checked: { var m = recurrence.value.match(/(?:^|;)BYDAY=([^;]+)/); return m ? m[1].split(",").indexOf(modelData) >= 0 : false } onClicked: recurrence.updateDay(modelData, checked) } }
        }
    }
    function updateDay(day, selected) {
        var match = value.match(/(?:^|;)BYDAY=([^;]+)/)
        var days = match ? match[1].split(",") : []
        var index = days.indexOf(day)
        if (selected && index < 0) days.push(day)
        if (!selected && index >= 0) days.splice(index, 1)
        var rule = "FREQ=WEEKLY;INTERVAL=" + interval.value
        if (days.length) rule += ";BYDAY=" + days.join(",")
        edited(rule)
    }
    function updateRule(index) {
        if (!index) { edited(""); return }
        var result = "FREQ=" + ["", "DAILY", "WEEKLY", "MONTHLY", "YEARLY"][index] + ";INTERVAL=" + interval.value
        if (index === 2) {
            var match = value.match(/(?:^|;)BYDAY=([^;]+)/)
            if (match) result += ";BYDAY=" + match[1]
        }
        edited(result)
    }
}
