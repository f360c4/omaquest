pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "../game/Chronicle.js" as Chronicle

// What happened, newest first, grouped by day.
//
// An entry on disk is a type, a seed and a few numbers; the sentence is built
// here, at render time, from the dictionary. That is why the chronicle rewrites
// itself in Portuguese when the panel language changes, and why three hundred
// entries are a few kilobytes rather than a novel.
Item {
  id: root

  property var game: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property int revision: game ? game.revision : 0

  readonly property var days: {
    revision
    if (!game || !game.chronicle) return []

    var grouped = Chronicle.groupByDay(game.chronicle, Math.floor(Date.now() / 1000))
    var seen = {}
    for (var i = 0; i < grouped.length; i++) seen[grouped[i].date] = true

    // A day whose entries have been pruned but whose song survives still gets
    // its heading: the song is the part worth keeping.
    var songDays = game.songFiles || []
    for (var s = 0; s < songDays.length; s++) {
      if (seen[songDays[s]]) continue
      if (!game.songFor(songDays[s])) continue
      grouped.push({ date: songDays[s], labelKey: "", entries: [], notable: [], counts: {}, order: [] })
    }

    grouped.sort(function (a, b) { return a.date < b.date ? 1 : (a.date > b.date ? -1 : 0) })
    return grouped
  }

  function t(key, vars) {
    return game ? game.t(key, vars) : key
  }

  function lineFor(entry) {
    return game ? Chronicle.render(entry, game.t.bind(game), game.world) : ""
  }

  function headingFor(day) {
    return day.labelKey ? root.t(day.labelKey) : day.date
  }

  readonly property bool bardShown: !!game && game.bardAvailable === true
    && game.bardEnabled === true
  readonly property string bardText: { revision; return game ? String(game.bardText || "") : "" }

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.space(10)

    // ---- The Bard. One button, at most once a day, and only if it was
    //      switched on and `omarchy` is actually installed. The song itself
    //      appears under its own day below, and stays there.
    Button {
      visible: root.bardShown && root.bardText.length === 0
      text: root.t("bard.ask")
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      bordered: true
      onClicked: if (root.game) root.game.askTheBard()
    }

    Text {
      width: parent.width
      visible: root.days.length === 0
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: root.t("ui.chronicle_empty")
      color: Qt.darker(root.foreground, 1.3)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      renderType: Text.NativeRendering
    }

    Repeater {
      model: root.days

      Column {
        id: dayGroup
        required property var modelData

        width: column.width
        spacing: Style.space(4)

        PanelSectionHeader {
          text: root.headingFor(dayGroup.modelData)
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        // The song for this day, if the Bard was asked for one. Under the
        // heading and above the lines, because it is about the day rather
        // than a thing that happened in it.
        Column {
          width: dayGroup.width
          spacing: Style.space(2)
          visible: text.length > 0

          readonly property string text: root.game
            ? String(root.game.songFor(dayGroup.modelData.date) || "") : ""

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.t("bard.title")
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            renderType: Text.NativeRendering
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            // Plain text: a language model wrote this into a file, and what it
            // put there is a sentence, not markup.
            textFormat: Text.PlainText
            text: parent.text
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            renderType: Text.NativeRendering
          }
        }

        // The day's routine, counted rather than recited.
        Text {
          width: dayGroup.width
          visible: text.length > 0
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: root.game ? Chronicle.summarise(dayGroup.modelData, root.game.t.bind(root.game)) : ""
          color: Qt.darker(root.foreground, 1.7)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
        }

        Repeater {
          model: dayGroup.modelData.notable

          Row {
            id: line
            required property var modelData

            width: dayGroup.width
            spacing: Style.space(6)

            // The clock is what makes a list of sentences read as a log.
            Text {
              width: Style.space(34)
              textFormat: Text.PlainText
              text: Qt.formatDateTime(new Date(line.modelData.ts * 1000), "HH:mm")
              color: Qt.darker(root.foreground, 1.8)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              renderType: Text.NativeRendering
            }

            Text {
              width: line.width - Style.space(34) - Style.space(6)
              wrapMode: Text.WordWrap
              // Plain text, always: a chronicle line can carry a boss's name,
              // which comes from an executable on this machine, and rich text
              // would make that name markup.
              textFormat: Text.PlainText
              text: root.lineFor(line.modelData)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              renderType: Text.NativeRendering
            }
          }
        }
      }
    }
  }
}
