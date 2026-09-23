pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "../game/Rules.js" as Rules
import "../game/World.js" as World

// The hero sheet: who they are, how they are, and what they are carrying.
//
// Everything is read through `game.hero()` rather than off the save directly,
// so health and energy are caught up to this instant — they regenerate by
// elapsed time, not by anything having run while the panel was closed.
Item {
  id: root

  property var game: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  // The service bumps `revision` on every change; binding through it is what
  // makes a plain JavaScript object re-read.
  readonly property int revision: game ? game.revision : 0
  readonly property var hero: { revision; return game ? game.hero() : null }
  readonly property var world: { revision; return game ? game.world : null }
  readonly property var xp: { revision; return game ? game.xpProgress() : null }

  // Something rose and has not been looked at. A line, not a nag — the arena
  // is a plus, and the one thing worse than forgetting it is being reminded
  // of it twice.
  readonly property bool waitingInArena: {
    revision
    if (!world) return false
    var bosses = world.bosses || []
    for (var i = 0; i < bosses.length; i++) if (bosses[i].seen !== true) return true
    return false
  }

  function t(key, vars) {
    return game ? game.t(key, vars) : key
  }

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.space(10)
    visible: !!root.hero

    // ---- The hero, four times life size, and who they are.
    Row {
      width: parent.width
      spacing: Style.space(12)

      PixelSprite {
        width: Style.space(64)
        height: Style.space(64)
        bank: root.game ? root.game.sprites : null
        body: root.hero ? root.hero.race : ""
        overlay: root.hero ? root.hero.cls : ""
        anim: root.game ? root.game.heroAnim : "idle"
        tint: root.foreground
        playing: root.visible
      }

      Column {
        width: parent.width - Style.space(64) - Style.space(12)
        spacing: Style.space(2)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.hero ? root.hero.name : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          renderType: Text.NativeRendering
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: root.hero
            ? root.t("ui.hero_subtitle", {
                level: root.hero.level,
                title: root.t("title." + root.hero.title),
                race: root.t("race." + root.hero.race + ".name"),
                cls: root.t("class." + root.hero.cls + ".name")
              })
            : ""
          color: Qt.darker(root.foreground, 1.3)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.world && root.world.realm
            ? root.t("ui.realm_line", {
                realm: root.world.realm.name,
                type: root.t("realm." + root.world.realm.type + ".name")
              })
            : ""
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
          }
      }
    }

    // ---- Two small things, side by side: somewhere to be, and something
    //      waiting. Neither ever nags; they sit here and are read or not.
    Row {
      width: parent.width
      spacing: Style.space(6)

      Button {
        text: root.t("ui.stroll")
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        bordered: true
        enabled: !!root.game && root.game.canStroll
        opacity: enabled ? 1 : 0.45
        tooltipText: enabled ? root.t("ui.stroll_note") : root.t("ui.stroll_later")
        onClicked: if (root.game) root.game.startStroll()
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.waitingInArena
        textFormat: Text.PlainText
        text: root.t("ui.arena_waiting")
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }
    }

    PanelSeparator { width: parent.width }

    // ---- The three bars.
    Column {
      width: parent.width
      spacing: Style.space(8)

      StatBar {
        width: parent.width
        label: root.t("ui.health")
        valueText: root.hero ? root.hero.hp + " / " + root.hero.hpMax : ""
        fraction: root.hero && root.hero.hpMax > 0 ? root.hero.hp / root.hero.hpMax : 0
        foreground: root.foreground
        fontFamily: root.fontFamily
        // Low health is the one place the panel raises its voice.
        fill: root.hero && root.hero.hpMax > 0 && root.hero.hp / root.hero.hpMax < 0.3
          ? Color.urgent : root.foreground
      }

      StatBar {
        width: parent.width
        label: root.t("ui.energy")
        valueText: root.hero ? root.hero.energy + " / " + root.hero.energyMax : ""
        fraction: root.hero && root.hero.energyMax > 0 ? root.hero.energy / root.hero.energyMax : 0
        foreground: root.foreground
        fontFamily: root.fontFamily
        fill: Color.accent
      }

      StatBar {
        width: parent.width
        label: root.hero && root.hero.level >= Rules.MAX_LEVEL
          ? root.t("ui.xp_capped") : root.t("ui.experience")
        valueText: root.xp && root.xp.needed > 0 ? root.xp.xp + " / " + root.xp.needed : ""
        fraction: root.xp ? root.xp.fraction : 0
        foreground: root.foreground
        fontFamily: root.fontFamily
        fill: Qt.darker(root.foreground, 1.6)
      }
    }

    PanelSeparator { width: parent.width }

    // ---- Attributes. Five rows rather than a grid: the names are long in
    //      Portuguese and a two-column layout clips them.
    Column {
      width: parent.width
      spacing: Style.space(3)

      PanelSectionHeader {
        text: root.t("ui.attributes")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Repeater {
        model: Rules.ATTRS

        Item {
          id: attrRow
          required property string modelData
          width: column.width
          height: attrLabel.implicitHeight

          readonly property bool isPrimary: root.hero
            && Rules.CLASSES[root.hero.cls]
            && Rules.CLASSES[root.hero.cls].primary === modelData

          Text {
            id: attrLabel
            textFormat: Text.PlainText
            text: root.t("attr." + attrRow.modelData)
            color: attrRow.isPrimary ? Color.accent : Qt.darker(root.foreground, 1.3)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            renderType: Text.NativeRendering
          }

          Text {
            anchors.right: parent.right
            textFormat: Text.PlainText
            text: root.hero && root.hero.attrs ? String(root.hero.attrs[attrRow.modelData]) : "-"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: attrRow.isPrimary
            renderType: Text.NativeRendering
          }
        }
      }
    }

    PanelSeparator { width: parent.width }

    // ---- Today's three. Progress is read off the day's counters, so a bar
    //      moves the moment the thing it counts happens, whether or not the
    //      panel was open when it did.
    Column {
      width: parent.width
      spacing: Style.space(6)

      PanelSectionHeader {
        text: root.world && root.world.day && root.world.day.sealEarned
          ? root.t("ui.quests_sealed") : root.t("ui.quests")
        foreground: root.world && root.world.day && root.world.day.sealEarned
          ? Color.accent : root.foreground
        fontFamily: root.fontFamily
      }

      Repeater {
        model: root.world && root.world.day ? root.world.day.quests : []

        StatBar {
          required property var modelData

          width: column.width
          compact: true
          label: root.t("quest." + modelData.id + ".name")
          valueText: modelData.done
            ? root.t("ui.quest_done")
            : Rules.num(modelData.progress) + " / " + Rules.num(modelData.target)
          fraction: Rules.num(modelData.target) > 0
            ? Rules.num(modelData.progress) / Rules.num(modelData.target) : 0
          foreground: root.foreground
          fontFamily: root.fontFamily
          fill: modelData.done ? Color.accent : Qt.darker(root.foreground, 1.6)
        }
      }
    }

    PanelSeparator { width: parent.width }

    // ---- What is worn, and what has been earned.
    Column {
      width: parent.width
      spacing: Style.space(3)
      visible: !!root.hero

      PanelSectionHeader {
        text: root.t("ui.equipment")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Repeater {
        model: Rules.SLOTS

        Item {
          id: slotRow
          required property string modelData

          width: column.width
          height: slotLabel.implicitHeight

          readonly property string worn: root.hero && root.hero.equipment
            ? (root.hero.equipment[modelData] || "") : ""

          Text {
            id: slotLabel
            textFormat: Text.PlainText
            text: root.t("slot." + slotRow.modelData)
            color: Qt.darker(root.foreground, 1.3)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            renderType: Text.NativeRendering
          }

          Text {
            anchors.right: parent.right
            textFormat: Text.PlainText
            text: slotRow.worn ? root.t("item." + slotRow.worn + ".name") : root.t("ui.empty_slot")
            color: slotRow.worn ? root.foreground : Qt.darker(root.foreground, 2.0)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            renderType: Text.NativeRendering
          }
        }
      }
    }

    Flow {
      width: parent.width
      spacing: Style.space(6)
      visible: !!root.world && (root.world.achievements || []).length > 0

      Repeater {
        model: root.world ? root.world.achievements : []

        Text {
          required property string modelData
          textFormat: Text.PlainText
          text: root.t("achievement." + modelData + ".name")
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
        }
      }
    }

    PanelSeparator { width: parent.width }

    // ---- Purse and streak.
    Item {
      width: parent.width
      height: goldLabel.implicitHeight

      Text {
        id: goldLabel
        textFormat: Text.PlainText
        text: root.t("ui.gold", { gold: root.hero ? root.hero.gold : 0 })
        color: Qt.darker(root.foreground, 1.3)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        renderType: Text.NativeRendering
      }

      Text {
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: root.world && root.world.streak
          ? root.t("ui.streak", { streak: root.world.streak.count }) : ""
        color: Qt.darker(root.foreground, 1.3)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        renderType: Text.NativeRendering
      }
    }
  }
}
