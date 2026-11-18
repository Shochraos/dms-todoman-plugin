import QtQuick
import qs.DCommon.Widgets

DButton {
    property bool highlighted: false
    variant: highlighted ? "tonal" : "text"
    buttonHeight: 40
    activeFocusOnTab: true
}