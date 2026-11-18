import QtQuick
import QtQuick.Controls
import qs.Common
import qs.DCommon.Widgets

Column {
    id: recurrence

    property string value: ""
    property bool replacing: false
    property int session: 0
    readonly property var frequencies: ["", "DAILY", "WEEKLY", "MONTHLY", "YEARLY"]
    readonly property var days: ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
    readonly property var parsedRule: parseRule(value)
    readonly property bool custom: parsedRule === null
    readonly property int frequencyIndex: custom ? -1 : frequencies.indexOf(parsedRule.frequency)
    readonly property int intervalValue: custom ? 1 : parsedRule.interval
    readonly property var selectedDays: custom ? [] : parsedRule.days

    signal edited(string value)

    spacing: Theme.spacingXS
    onSessionChanged: replacing = false
    onCustomChanged: if (!custom) replacing = false

    function parseRule(rule) {
        if (!rule)
            return {frequency: "", interval: 1, days: []};
        const parts = Object.create(null);
        for (const segment of rule.split(";")) {
            const match = /^(FREQ|INTERVAL|BYDAY)=(.+)$/.exec(segment);
            if (!match || parts[match[1]] !== undefined)
                return null;
            parts[match[1]] = match[2];
        }
        if (frequencies.indexOf(parts.FREQ) <= 0)
            return null;
        const interval = parts.INTERVAL === undefined ? "1" : parts.INTERVAL;
        if (!/^[1-9][0-9]{0,2}$/.test(interval))
            return null;
        const selected = parts.BYDAY === undefined ? [] : parts.BYDAY.split(",");
        if (selected.length && (parts.FREQ !== "WEEKLY" || selected.some(day => !days.includes(day)) || new Set(selected).size !== selected.length))
            return null;
        return {frequency: parts.FREQ, interval: Number(interval), days: selected};
    }

    function updateRule(index, interval, selected) {
        if (index < 0 || (custom && !replacing))
            return;
        if (!index) {
            edited("");
            return;
        }
        let rule = "FREQ=" + frequencies[index] + ";INTERVAL=" + interval;
        if (index === 2 && selected.length)
            rule += ";BYDAY=" + selected.join(",");
        edited(rule);
    }

    StyledText {
        text: "Repeat"
        color: Theme.surfaceText
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
    }

    StyledText {
        width: parent.width
        visible: recurrence.custom
        text: recurrence.replacing ? "Choose a new repeat setting to replace the custom rule." : "This task has a custom repeat rule. It stays unchanged unless you replace it."
        wrapMode: Text.Wrap
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall
    }

    DButton {
        id: replaceButton
        visible: recurrence.custom && !recurrence.replacing
        text: "Replace rule"
        variant: "text"
        maximumWidth: parent.width
        onClicked: {
            recurrence.replacing = true;
            frequency.focusTarget.forceActiveFocus(Qt.TabFocusReason);
        }
    }

    Column {
        width: parent.width
        spacing: Theme.spacingS
        visible: !recurrence.custom || recurrence.replacing

        TodomanCombo {
            id: frequency
            width: parent.width
            triggerHeight: Math.max(Theme.buttonHeightS, Theme.fontSizeMedium + Theme.spacingM * 2)
            model: ["Does not repeat", "Daily", "Weekly", "Monthly", "Yearly"]
            currentIndex: recurrence.frequencyIndex
            Accessible.name: "Repeat frequency"
            onActivated: index => recurrence.updateRule(index, recurrence.intervalValue, recurrence.selectedDays)
        }

        DButton {
            visible: recurrence.custom && recurrence.replacing
            text: "Keep custom rule"
            variant: "text"
            maximumWidth: parent.width
            onClicked: {
                recurrence.replacing = false;
                replaceButton.forceActiveFocus(Qt.TabFocusReason);
            }
        }

        Column {
            width: parent.width
            visible: recurrence.frequencyIndex > 0
            spacing: Theme.spacingXS

            StyledText {
                text: ["", "Every (days)", "Every (weeks)", "Every (months)", "Every (years)"][Math.max(0, recurrence.frequencyIndex)]
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }

            SpinBox {
                id: interval
                width: Math.min(parent.width, Math.max(implicitWidth, Theme.fontSizeMedium * 8))
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
                palette.text: Theme.surfaceText
                palette.buttonText: Theme.surfaceText
                palette.button: Theme.surfaceContainerHigh
                palette.base: Theme.surfaceContainerHigh
                palette.highlight: Theme.primary
                palette.highlightedText: Theme.onPrimary
                from: 1
                to: 999
                editable: true
                value: recurrence.intervalValue
                onValueModified: recurrence.updateRule(recurrence.frequencyIndex, value, recurrence.selectedDays)
                Accessible.name: "Repeat interval"

                background: Rectangle {
                    color: Theme.surfaceContainerHigh
                    radius: Theme.cornerRadiusS
                    border.color: interval.activeFocus ? Theme.primary : Theme.outlineVariant
                    border.width: interval.activeFocus ? 2 : 1
                }
            }
        }

        Column {
            width: parent.width
            visible: recurrence.frequencyIndex === 2
            spacing: Theme.spacingXS

            StyledText {
                width: parent.width
                text: "Days (optional)"
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
            }

            DFilterChips {
                model: recurrence.days.map((day, index) => ({
                    value: day,
                    label: Qt.locale().dayName(index + 1, Locale.ShortFormat),
                    tooltip: Qt.locale().dayName(index + 1, Locale.LongFormat)
                }))
                width: parent.width
                chipHeight: Math.max(Theme.buttonHeightXS, Theme.fontSizeSmall + Theme.spacingS * 2)
                chipPadding: Theme.spacingS
                multiSelect: true
                selectedValues: recurrence.selectedDays
                onSelectionToggled: (index, selected) => {
                    const day = recurrence.days[index];
                    const previous = recurrence.selectedDays;
                    const updated = recurrence.days.filter(candidate => candidate === day ? selected : previous.includes(candidate));
                    recurrence.updateRule(2, recurrence.intervalValue, updated);
                }
            }
        }
    }
}
