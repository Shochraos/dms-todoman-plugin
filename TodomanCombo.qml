import QtQuick
import qs.DCommon.Widgets

DDropdown {
    id: control
    property var model: []
    property int currentIndex: -1
    readonly property string currentText: currentIndex >= 0 && currentIndex < model.length ? String(model[currentIndex]) : ""
    signal activated(int index)
    options: model
    currentValue: currentText
    showLabel: true
    dropdownWidth: width
    triggerHeight: 40
    focusPolicy: Qt.StrongFocus
    onCurrentTextChanged: currentValue = currentText
    onValueChanged: value => {
        var index = model.indexOf(value)
        if (index >= 0)
            activated(index)
        currentValue = currentText
    }
}