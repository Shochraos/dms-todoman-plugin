import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "dankTodoman"

    StringSetting {
        settingKey: "listFilter"
        label: "Lists"
        description: "Comma-separated list names to show (empty = all lists)"
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
