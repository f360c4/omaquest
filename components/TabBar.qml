pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

// The panel's tabs. A row of buttons, because this game is played with a
// mouse: no tab needs a keyboard to reach.
//
// A tab can carry a dot, for when something happened there that has not been
// looked at yet — a boss that appeared, an expedition that came home.
Item {
  id: root

  property var tabs: []              // [{ id, label, marked }]
  property string current: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal selected(string id)

  implicitHeight: row.implicitHeight

  // Wrapped, not scrolled. Six tabs fit across 380 pixels in English and do
  // not in Portuguese — "Expedição" and "Crônica" are simply longer — and a
  // row that scrolls hides tabs behind a gesture nobody looks for. Two short
  // rows show all six at once, in any language.
  Flow {
    id: row
    width: parent.width
    spacing: Style.space(2)

    Repeater {
      model: root.tabs

      Button {
        id: tab
        required property var modelData

        text: modelData.label
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        horizontalPadding: Style.space(9)
        selected: modelData.id === root.current
        onClicked: root.selected(modelData.id)

        Rectangle {
          visible: tab.modelData.marked === true
          width: Style.space(5)
          height: width
          radius: width / 2
          color: Color.accent
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.rightMargin: Style.space(3)
          anchors.topMargin: Style.space(3)
        }
      }
    }
  }
}
