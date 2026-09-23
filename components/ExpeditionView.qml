pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "../game/Rules.js" as Rules

// Three places to go, or a countdown, or something to collect.
//
// This is the one part of the game that runs while nobody is watching, and the
// only one that survives the machine being off: what is stored is an end time
// and a seed, so a laptop closed mid-journey and opened a week later finds the
// result it would have found on time.
Item {
  id: root

  property var game: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property int revision: game ? game.revision : 0
  readonly property var world: { revision; return game ? game.world : null }
  readonly property var hero: { revision; return game ? game.hero() : null }
  readonly property var expedition: world ? world.expedition : null

  readonly property bool fighting: !!world && !!world.arena
  readonly property bool fainted: !!hero && Rules.num(hero.faintedUntil) > root.now
  readonly property bool hasEnergy: !!hero && Rules.num(hero.energy) >= 1

  // Ticks once a second while this view is on screen, and only then: the
  // countdown is the one thing here that needs to move by itself.
  property double now: Math.floor(Date.now() / 1000)

  Timer {
    interval: 1000
    repeat: true
    running: root.visible
    onTriggered: root.now = Math.floor(Date.now() / 1000)
  }

  readonly property var destinations: {
    revision
    if (!world || !world.hero) return []
    return Rules.destinations(world.day.date, world.hero)
  }

  readonly property int remaining: expedition ? Math.max(0, Rules.num(expedition.endsAt) - root.now) : 0

  function t(key, vars) {
    return game ? game.t(key, vars) : key
  }

  function countdown(seconds) {
    var hours = Math.floor(seconds / 3600)
    var minutes = Math.floor((seconds % 3600) / 60)
    var rest = seconds % 60
    function pad(value) { return (value < 10 ? "0" : "") + value }
    return hours > 0 ? hours + ":" + pad(minutes) + ":" + pad(rest) : minutes + ":" + pad(rest)
  }

  function duration(minutes) {
    return minutes >= 60
      ? root.t("expedition.hours", { hours: Math.round(minutes / 60) })
      : root.t("expedition.minutes", { minutes: minutes })
  }

  function lootLine(result) {
    if (!result) return ""
    var parts = [root.t("expedition.loot_gold", { gold: Rules.num(result.gold) })]
    for (var material in result.materials)
      parts.push(root.t("material." + material) + " ×" + Rules.num(result.materials[material]))
    if (result.item) parts.push(root.t("item." + result.item + ".name"))
    return parts.join(" · ")
  }

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.space(10)

    // ---- Nothing out: pick somewhere.
    Column {
      width: parent.width
      spacing: Style.space(6)
      visible: !root.expedition

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        visible: root.fighting || root.fainted || !root.hasEnergy
        text: root.fighting ? root.t("expedition.fighting")
          : (root.fainted ? root.t("arena.fainted") : root.t("arena.no_energy"))
        color: Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        renderType: Text.NativeRendering
      }

      Repeater {
        model: root.destinations

        Item {
          id: card
          required property var modelData

          width: column.width
          height: Math.max(Style.space(38), cardRow.implicitHeight)

          Row {
            id: cardRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Column {
              width: cardRow.width - goButton.width - Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.t("dest." + card.modelData.place)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                renderType: Text.NativeRendering
              }

              Text {
                width: parent.width
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: root.duration(card.modelData.minutes) + " · "
                  + root.t("expedition.risk_" + card.modelData.risk)
                color: Qt.darker(root.foreground, 1.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                renderType: Text.NativeRendering
              }
            }

            Button {
              id: goButton
              anchors.verticalCenter: parent.verticalCenter
              text: root.t("expedition.depart")
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              enabled: root.hasEnergy && !root.fighting && !root.fainted
              opacity: enabled ? 1 : 0.45
              onClicked: if (root.game)
                root.game.dispatch({ type: "start_expedition", destId: card.modelData.id })
            }
          }
        }
      }
    }

    // ---- Out there.
    Column {
      width: parent.width
      spacing: Style.space(6)
      visible: !!root.expedition && !root.expedition.resolved

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: root.expedition
          ? root.t("expedition.away", {
              name: root.hero ? root.hero.name : "",
              place: root.t("dest." + root.expedition.place)
            })
          : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        renderType: Text.NativeRendering
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.countdown(root.remaining)
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.display
        renderType: Text.NativeRendering
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: root.t("expedition.offline_note")
        color: Qt.darker(root.foreground, 1.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }
    }

    // ---- Home, with something in hand.
    Column {
      width: parent.width
      spacing: Style.space(6)
      visible: !!root.expedition && root.expedition.resolved === true

      PanelSectionHeader {
        text: root.expedition ? root.t("dest." + root.expedition.place) : ""
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: root.expedition && root.expedition.result
          ? root.t("expedition.brought", { xp: Rules.num(root.expedition.result.xp) })
            + "\\n" + root.lootLine(root.expedition.result)
          : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        renderType: Text.NativeRendering
      }

      Button {
        text: root.t("expedition.collect")
        foreground: root.foreground
        fontFamily: root.fontFamily
        bordered: true
        active: true
        onClicked: if (root.game) root.game.dispatch({ type: "collect_expedition" })
      }
    }
  }
}
