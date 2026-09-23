import QtQuick
import qs.Commons

// A labelled progress bar: health, energy, experience, quest progress.
//
// Drawn rather than composed from a UI component because the shell has no
// horizontal meter of its own, and this one has to read at 380 pixels wide
// with a caption on each end.
Item {
  id: root

  property string label: ""
  property string valueText: ""
  property real fraction: 0
  property color foreground: Color.foreground
  property color fill: Color.accent
  property string fontFamily: Style.font.family
  property bool compact: false

  readonly property real clamped: Math.max(0, Math.min(1, fraction))

  // A bar with nothing written over it is just a bar: the caption row
  // collapses rather than leaving a line of empty space above it, which is
  // what the feats want — the name is already above them.
  readonly property bool titled: label.length > 0 || valueText.length > 0

  implicitHeight: (titled ? caption.implicitHeight + Style.space(3) : 0) + track.height

  Text {
    id: caption
    width: parent.width
    visible: root.titled
    // Hidden is not gone: an invisible item keeps its geometry, and the track
    // anchors to the bottom of this one.
    height: root.titled ? implicitHeight : 0
    textFormat: Text.PlainText
    text: root.label
    color: Qt.darker(root.foreground, 1.4)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    renderType: Text.NativeRendering
  }

  Text {
    id: value
    visible: root.titled
    anchors.right: parent.right
    anchors.top: parent.top
    textFormat: Text.PlainText
    text: root.valueText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    renderType: Text.NativeRendering
  }

  Rectangle {
    id: track
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: caption.bottom
    anchors.topMargin: root.titled ? Style.space(3) : 0
    height: root.compact ? Style.space(4) : Style.space(6)
    radius: height / 2
    color: Util.alpha(root.foreground, 0.15)

    Rectangle {
      width: Math.round(parent.width * root.clamped)
      height: parent.height
      radius: parent.radius
      color: root.fill

      Behavior on width {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
      }
    }
  }
}
