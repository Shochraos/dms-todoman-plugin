import QtQuick
import qs.Common
import qs.DCommon.Widgets

Column {
    id: picker

    property string label: "Date"
    property var value: null
    required property var controller
    property string fieldName: "due"
    property bool expanded: false
    property date month: firstOfMonth(new Date())
    readonly property var raw: controller.dateInputs[fieldName] || null
    readonly property date localInstant: value && value.kind === "datetime" && /(?:Z|[+-]\d{2}:\d{2})$/i.test(value.value) ? new Date(value.value) : new Date(NaN)
    readonly property bool hasLocalInstant: !isNaN(localInstant.getTime())
    readonly property string dateText: raw ? raw.date : !value ? "" : hasLocalInstant ? iso(localInstant) : value.value.slice(0, 10)
    readonly property string timeText: raw ? raw.time : !value || value.kind !== "datetime" ? "09:00" : hasLocalInstant ? pad(localInstant.getHours()) + ":" + pad(localInstant.getMinutes()) : value.value.slice(11, 16)
    readonly property int selectedMode: raw ? raw.mode : !value ? 0 : value.kind === "date" ? 1 : 2
    readonly property date parsedDate: parseDate(dateText)
    readonly property bool invalidDate: !!raw && selectedMode > 0 && isNaN(parsedDate.getTime())
    readonly property bool invalidTime: !!raw && selectedMode === 2 && !raw.valid && !invalidDate

    signal edited(var value)

    spacing: Theme.spacingXS

    Connections {
        target: picker.controller
        function onEditorSessionChanged() { picker.resetCalendar() }
    }

    onSelectedModeChanged: if (selectedMode === 0) resetCalendar()

    function pad(number) {
        return String(number).padStart(2, "0")
    }

    function iso(date) {
        return String(date.getFullYear()).padStart(4, "0") + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
    }

    function parseDate(text) {
        const parts = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
        if (!parts || Number(parts[1]) < 1)
            return new Date(NaN);
        const date = new Date(2000, 0, 1, 12);
        date.setFullYear(Number(parts[1]), Number(parts[2]) - 1, Number(parts[3]));
        return iso(date) === text ? date : new Date(NaN);
    }

    function firstOfMonth(date, offset = 0) {
        const month = new Date(date);
        month.setDate(1);
        month.setMonth(month.getMonth() + offset);
        return month;
    }

    function resetCalendar() {
        expanded = false;
        month = firstOfMonth(new Date());
    }

    function toggleCalendar() {
        if (!expanded)
            month = firstOfMonth(isNaN(parsedDate.getTime()) ? new Date() : parsedDate);
        expanded = !expanded;
    }

    function change(mode, dateText, timeText) {
        let next = null;
        const date = parseDate(dateText);
        if (mode === 1 && !isNaN(date.getTime())) {
            next = {kind: "date", value: dateText};
        } else if (mode === 2 && !isNaN(date.getTime())) {
            const time = /^(\d{2}):(\d{2})$/.exec(timeText);
            if (time && Number(time[1]) <= 23 && Number(time[2]) <= 59) {
                date.setHours(Number(time[1]), Number(time[2]), 0, 0);
                if (iso(date) === dateText && date.getHours() === Number(time[1]) && date.getMinutes() === Number(time[2])) {
                    const offset = -date.getTimezoneOffset();
                    const minutes = Math.abs(offset);
                    next = {kind: "datetime", value: dateText + "T" + timeText + ":00" + (offset < 0 ? "-" : "+") + pad(Math.floor(minutes / 60)) + ":" + pad(minutes % 60)};
                }
            }
        }
        const valid = mode === 0 || next !== null;
        const inputs = Object.assign({}, controller.dateInputs);
        inputs[fieldName] = {mode: mode, date: dateText, time: timeText, valid: valid};
        controller.dateInputs = inputs;
        if (valid)
            edited(next);
    }

    function pickDay(date) {
        change(selectedMode, iso(date), timeText);
        calendarButton.forceActiveFocus(Qt.TabFocusReason);
        expanded = false;
    }

    StyledText {
        width: parent.width
        text: picker.label
        color: Theme.surfaceText
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
    }

    TodomanCombo {
        width: parent.width
        triggerHeight: Math.max(Theme.buttonHeightS, Theme.fontSizeMedium + Theme.spacingM * 2)
        model: ["None", "Date only", "Date and time"]
        currentIndex: picker.selectedMode
        Accessible.name: picker.label + " mode"
        onActivated: index => picker.change(index, picker.dateText || picker.iso(new Date()), picker.timeText)
    }

    Flow {
        id: dateRow
        width: parent.width
        spacing: Theme.spacingS
        visible: picker.selectedMode > 0
        readonly property real inlineWidth: width - calendarButton.width - spacing

        TodomanField {
            width: dateRow.inlineWidth >= Theme.fontSizeMedium * 10 ? dateRow.inlineWidth : dateRow.width
            placeholderText: "YYYY-MM-DD"
            hidePlaceholderOnFocus: false
            text: picker.dateText
            isError: picker.invalidDate
            Accessible.name: picker.label + " date"
            Accessible.description: "YYYY-MM-DD"
            onTextEdited: if (inputFocused) picker.change(picker.selectedMode, text, picker.timeText)
        }

        DButton {
            id: calendarButton
            text: "Calendar"
            iconName: "calendar_month"
            variant: "text"
            maximumWidth: dateRow.width
            buttonHeight: Math.max(Theme.buttonHeightS, Theme.fontSizeMedium + Theme.spacingM)
            checkable: true
            checked: picker.expanded
            Accessible.name: picker.label + " calendar"
            Accessible.checkable: true
            Accessible.checked: checked
            onClicked: picker.toggleCalendar()
        }
    }

    StyledText {
        width: parent.width
        visible: picker.invalidDate
        text: "Enter a date as YYYY-MM-DD."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.error
        wrapMode: Text.Wrap
    }

    Column {
        width: parent.width
        visible: picker.selectedMode === 2
        spacing: Theme.spacingXS

        StyledText {
            text: "Local time"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        TodomanField {
            width: parent.width
            placeholderText: "HH:mm"
            hidePlaceholderOnFocus: false
            text: picker.timeText
            isError: picker.invalidTime
            Accessible.name: picker.label + " local time"
            Accessible.description: "HH:mm, 24-hour time"
            onTextEdited: if (inputFocused) picker.change(picker.selectedMode, picker.dateText, text)
        }

        StyledText {
            width: parent.width
            visible: picker.invalidTime
            text: "Enter a valid local time as HH:mm."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.error
            wrapMode: Text.Wrap
        }
    }

    Column {
        width: parent.width
        visible: picker.expanded && picker.selectedMode > 0
        spacing: Theme.spacingS

        Keys.onEscapePressed: event => {
            calendarButton.forceActiveFocus(Qt.TabFocusReason);
            picker.expanded = false;
            event.accepted = true;
        }

        Row {
            width: parent.width
            spacing: Theme.spacingXS

            DActionButton {
                id: previousMonth
                iconName: "chevron_left"
                tooltipText: "Previous month"
                onClicked: picker.month = picker.firstOfMonth(picker.month, -1)
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - previousMonth.width - nextMonth.width - parent.spacing * 2)
                text: Qt.formatDate(picker.month, "MMMM yyyy")
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            DActionButton {
                id: nextMonth
                iconName: "chevron_right"
                tooltipText: "Next month"
                onClicked: picker.month = picker.firstOfMonth(picker.month, 1)
            }
        }

        DMonthGrid {
            width: parent.width
            height: weekdayRowHeight + rows * (Theme.fontSizeMedium + Theme.spacingM + cellGap)
            weekdayRowHeight: Theme.fontSizeSmall + Theme.spacingS
            displayDate: picker.month
            selectedDate: picker.parsedDate
            today: new Date(picker.controller.clock)
            dayNames: cellWidth >= Theme.fontSizeSmall * 3.2 ? [] : [1, 2, 3, 4, 5, 6, 7].map(day => Qt.locale().dayName(day, Locale.NarrowFormat))
            onDayClicked: date => picker.pickDay(date)
        }

        Flow {
            width: parent.width
            spacing: Theme.spacingXS

            DButton {
                text: "Today"
                variant: "text"
                maximumWidth: parent.width
                onClicked: picker.pickDay(new Date())
            }

            DButton {
                text: "Tomorrow"
                variant: "text"
                maximumWidth: parent.width
                onClicked: {
                    const date = new Date();
                    date.setDate(date.getDate() + 1);
                    picker.pickDay(date);
                }
            }
        }
    }
}
