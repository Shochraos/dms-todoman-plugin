import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "dankTodoman"

    StringSetting {
        settingKey: "pythonExecutable"
        label: "Python interpreter"
        description: "Interpreter with icalendar and python-dateutil installed"
        placeholder: "python3"
        defaultValue: "python3"
    }

    StringSetting {
        settingKey: "listFilter"
        label: "Lists"
        description: "Separate list names with commas, or leave blank to watch all lists. Agenda filters only change what you see in the popout."
        placeholder: "work, personal"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "defaultList"
        label: "Default list for new tasks"
        description: "Used when creating a task if no list is picked (empty = todoman default)"
        placeholder: "personal"
        defaultValue: ""
    }

    SelectionSetting {
        settingKey: "sortField"
        label: "Sort by"
        description: "Field used to order tasks"
        options: [
            {label: "Due date", value: "due"},
            {label: "Priority", value: "priority"},
            {label: "Created", value: "created_at"},
            {label: "Summary", value: "summary"}
        ]
        defaultValue: "due"
    }

    ToggleSetting {
        settingKey: "showCompleted"
        label: "Show completed tasks"
        description: "Include done/cancelled tasks in the list"
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "showNearestTask"
        label: "Show next task in the bar"
        description: "Append the next due task and a countdown to the bar pill. Overdue tasks are only shown when nothing is still upcoming."
        defaultValue: false
    }

    SliderSetting {
        settingKey: "refreshInterval"
        label: "Refresh interval"
        description: "How often to reload tasks"
        minimum: 1
        maximum: 60
        unit: "min"
        defaultValue: 5
    }
}
