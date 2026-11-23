import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "dankTodoman"

    StringSetting {
        settingKey: "pythonExecutable"
        label: "Python interpreter"
        description: "Leave blank to use the default interpreter. To override it, enter the path to Python 3.10 or newer with icalendar and python-dateutil."
        placeholder: "Default interpreter"
        defaultValue: ""
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

    SelectionSetting {
        settingKey: "futureTasks"
        label: "Future-start tasks"
        description: "Show or hide tasks whose start date has not arrived yet"
        options: [
            {label: "Follow Todoman config", value: "config"},
            {label: "Show", value: "show"},
            {label: "Hide", value: "hide"}
        ]
        defaultValue: "config"
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
