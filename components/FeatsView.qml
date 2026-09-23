pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "../game/Rules.js" as Rules

// The feats: what has been earned, and what the rest are waiting for.
//
// They used to be a row of names at the bottom of the Hero sheet, which is
// how somebody ends up asking what "Collector" is and where it came from.
// A name on its own is a trophy in a language you do not read.
//
// So each one says its condition in a sentence, and the ones still open carry
// the count. The count is the part that makes this a tab worth opening twice:
// "10 workspaces in a day" is a rule, "7 / 10" is an afternoon.
Item {
  id: root

  property var game: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property int revision: game ? game.revision : 0
  readonly property var world: { revision; return game ? game.world : null }

  readonly property var board: { revision; return Rules.achievementBoard(root.world) }
  readonly property int earned: {
    var n = 0
    for (var i = 0; i < board.length; i++) if (board[i].done) n++
    return n
  }

  function t(key, vars) {
    return game ? game.t(key, vars) : key
  }

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.space(8)

    Item {
      width: parent.width
      height: header.implicitHeight

      PanelSectionHeader {
        id: header
        text: root.t("ui.feats")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Text {
        anchors.right: parent.right
        anchors.baseline: header.baseline
        textFormat: Text.PlainText
        text: root.earned + " / " + root.board.length
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }
    }

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: root.t("ui.feats_note")
      color: Qt.darker(root.foreground, 1.6)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }

    Repeater {
      model: root.board

      Column {
        id: featRow
        required property var modelData

        // Nothing to count, so nothing to draw a bar for: you have beaten a
        // guardian or you have not.
        readonly property bool measured: Rules.num(modelData.target) > 0 && !modelData.done

        width: column.width
        spacing: Style.space(2)
        topPadding: Style.space(4)

        Item {
          width: parent.width
          height: featName.implicitHeight

          Text {
            id: featName
            anchors.left: parent.left
            anchors.right: featCount.left
            anchors.rightMargin: Style.space(8)
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: root.t("achievement." + featRow.modelData.id + ".name")
            color: featRow.modelData.done ? Color.accent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            renderType: Text.NativeRendering
          }

          Text {
            id: featCount
            anchors.right: parent.right
            anchors.baseline: featName.baseline
            textFormat: Text.PlainText
            text: featRow.modelData.done
              ? root.t("ui.feat_earned")
              : (featRow.measured
                  ? Rules.num(featRow.modelData.progress) + " / " + Rules.num(featRow.modelData.target)
                  : "")
            color: featRow.modelData.done ? Color.accent : Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            renderType: Text.NativeRendering
          }
        }

        // Where it comes from. The whole reason this tab exists.
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: root.t("achievement." + featRow.modelData.id + ".note")
          color: Qt.darker(root.foreground, featRow.modelData.done ? 1.5 : 1.8)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
        }

        // Only for what is still open, and only where there is a number. A
        // full bar on something already earned is a bar that says nothing.
        StatBar {
          width: parent.width
          visible: featRow.measured
          compact: true
          label: ""
          valueText: ""
          fraction: Rules.num(featRow.modelData.target) > 0
            ? Rules.num(featRow.modelData.progress) / Rules.num(featRow.modelData.target) : 0
          foreground: root.foreground
          fontFamily: root.fontFamily
          fill: Qt.darker(root.foreground, 1.7)
        }
      }
    }
  }
}
