pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "../game/Rules.js" as Rules

// Two screens in one tab: what is waiting, and the fight itself.
//
// A fight is four buttons and a four-line log. Nothing here needs a keyboard,
// and nothing here is on a clock — the enemy moves when you do.
Item {
  id: root

  property var game: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property int revision: game ? game.revision : 0
  readonly property var world: { revision; return game ? game.world : null }
  readonly property var hero: { revision; return game ? game.hero() : null }
  readonly property var arena: world ? world.arena : null

  readonly property bool away: !!world && !!world.expedition && world.expedition.resolved !== true
  readonly property bool fainted: !!hero && Rules.num(hero.faintedUntil) > Math.floor(Date.now() / 1000)
  readonly property bool hasEnergy: !!hero && Rules.num(hero.energy) >= 1
  readonly property int draughts: hero && hero.potions
    ? Rules.num(hero.potions.healing_draught) : 0

  function t(key, vars) {
    return game ? game.t(key, vars) : key
  }

  // Bosses first — they are the ones with a clock on them — then the day's
  // three wanderers.
  readonly property var threats: {
    revision
    if (!world || !world.hero) return []
    var out = []
    var bosses = world.bosses || []
    for (var b = 0; b < bosses.length; b++) {
      out.push({
        id: bosses[b].id,
        kind: bosses[b].kind,
        tier: bosses[b].tier,
        sprite: bosses[b].kind === "guardian" ? "boss_guardian" : "boss_daemon",
        label: bosses[b].kind === "guardian"
          ? root.t("enemy.boss_guardian.name")
          : root.t("boss.pattern", {
              comm: root.capitalised(bosses[b].comm),
              epithet: root.t("boss.epithet." + Rules.num(bosses[b].epithet))
            }),
        days: Math.max(0, Math.ceil((Rules.num(bosses[b].expiresAt) - Math.floor(Date.now() / 1000)) / 86400)),
        unseen: bosses[b].seen !== true
      })
    }

    var wanderers = Rules.wanderers(world.day.date, world.hero.level)
    for (var w = 0; w < wanderers.length; w++) {
      out.push({
        id: wanderers[w].id,
        kind: "wanderer",
        tier: wanderers[w].tier,
        sprite: wanderers[w].kind,
        label: root.t("enemy." + wanderers[w].kind + ".name"),
        days: 0,
        unseen: false
      })
    }
    return out
  }

  // The executable's basename, title-cased for the sentence it lands in. It
  // reaches the panel as plain text and is never treated as anything else.
  function capitalised(text) {
    var value = String(text || "")
    return value ? value.charAt(0).toUpperCase() + value.slice(1) : ""
  }

  readonly property string lootLine: {
    revision
    if (!arena || !arena.loot) return ""
    var loot = arena.loot
    var parts = []
    if (Rules.num(loot.xp) > 0) parts.push(root.t("arena.loot_xp", { xp: Rules.num(loot.xp) }))
    if (Rules.num(loot.gold) > 0) parts.push(root.t("expedition.loot_gold", { gold: Rules.num(loot.gold) }))
    for (var material in (loot.materials || {}))
      parts.push(root.t("material." + material) + " x" + Rules.num(loot.materials[material]))
    if (loot.item) parts.push(root.t("item." + loot.item + ".name"))
    return parts.join(" · ")
  }

  function logLine(entry) {
    if (!entry) return ""
    var key = "combat." + String(entry.key)
    return root.t(key, {
      damage: Rules.num(entry.damage),
      heal: Rules.num(entry.heal),
      name: root.hero ? root.hero.name : "",
      enemy: root.arena ? root.t("enemy." + root.arena.enemy.kind + ".name") : ""
    })
  }

  implicitHeight: root.arena ? fight.implicitHeight : list.implicitHeight

  // ================================================================== list

  Column {
    id: list
    width: parent.width
    spacing: Style.space(8)
    visible: !root.arena

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      visible: root.away || root.fainted || !root.hasEnergy
      text: root.away ? root.t("arena.away")
        : (root.fainted ? root.t("arena.fainted") : root.t("arena.no_energy"))
      color: Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      renderType: Text.NativeRendering
    }

    Repeater {
      model: root.threats

      Item {
        id: card
        required property var modelData

        width: list.width
        height: Math.max(Style.space(44), cardRow.implicitHeight)

        Row {
          id: cardRow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          PixelSprite {
            width: Style.space(32)
            height: Style.space(32)
            anchors.verticalCenter: parent.verticalCenter
            bank: root.game ? root.game.sprites : null
            body: card.modelData.sprite
            tint: root.foreground
            playing: root.visible
          }

          Column {
            width: cardRow.width - Style.space(32) - fightButton.width - Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)

            Row {
              width: parent.width
              spacing: Style.space(4)

              Text {
                // A boss is named after an executable, and executables have
                // names like xdg-desktop-portal-hyprland. Elided rather than
                // wrapped: the epithet is the part worth reading, and a name
                // that grew a second line would push the row into the next.
                width: Math.max(0, parent.width - (dot.visible ? dot.width + Style.space(4) : 0))
                elide: Text.ElideMiddle
                textFormat: Text.PlainText
                text: card.modelData.label
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                renderType: Text.NativeRendering
              }

              // The same dot the bar shows: something arrived and has not been
              // looked at.
              Rectangle {
                id: dot
                visible: card.modelData.unseen
                width: Style.space(5)
                height: width
                radius: width / 2
                color: Color.accent
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: card.modelData.kind === "wanderer"
                ? root.t("arena.tier", { tier: card.modelData.tier })
                : root.t("arena.tier_days", { tier: card.modelData.tier, days: card.modelData.days })
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              renderType: Text.NativeRendering
            }
          }

          Button {
            id: fightButton
            anchors.verticalCenter: parent.verticalCenter
            text: root.t("arena.fight")
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            // Disabled rather than hidden, with the reason above the list, so
            // the arena never becomes a tab that mysteriously does nothing.
            // `qs.Ui.Button` has no disabled state of its own — `interactive`
            // belongs to WidgetButton — so this is Item.enabled, which stops
            // the click, plus the dimming that makes it look stopped.
            enabled: root.hasEnergy && !root.away && !root.fainted
            opacity: enabled ? 1 : 0.45
            tooltipText: root.hasEnergy ? "" : root.t("arena.no_energy")
            onClicked: {
              if (!root.game) return
              root.game.dispatch({ type: "mark_seen", what: "bosses" })
              root.game.dispatch({ type: "start_fight", kind: card.modelData.kind, id: card.modelData.id })
            }
          }
        }
      }
    }
  }

  // ================================================================= fight

  Column {
    id: fight
    width: parent.width
    spacing: Style.space(10)
    visible: !!root.arena

    // ---- The two of them, facing each other.
    Item {
      width: parent.width
      height: Style.space(48)

      PixelSprite {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(48)
        height: Style.space(48)
        bank: root.game ? root.game.sprites : null
        body: root.hero ? root.hero.race : ""
        overlay: root.hero ? root.hero.cls : ""
        anim: root.game ? root.game.heroAnim : "fight"
        tint: root.foreground
        playing: fight.visible
      }

      PixelSprite {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(48)
        height: Style.space(48)
        bank: root.game ? root.game.sprites : null
        body: root.arena ? root.arena.enemy.kind : ""
        anim: "fight"
        // Turned to face the hero, which is the whole reason mirroring exists.
        mirrored: true
        tint: root.foreground
        playing: fight.visible
      }
    }

    // ---- Two health bars, and whose turn it has been.
    Row {
      width: parent.width
      spacing: Style.space(10)

      StatBar {
        width: (parent.width - Style.space(10)) / 2
        label: root.hero ? root.hero.name : ""
        valueText: root.arena ? String(root.arena.heroHp) : ""
        fraction: root.arena && root.hero && root.hero.hpMax > 0
          ? root.arena.heroHp / root.hero.hpMax : 0
        foreground: root.foreground
        fontFamily: root.fontFamily
        fill: root.arena && root.hero && root.hero.hpMax > 0 && root.arena.heroHp / root.hero.hpMax < 0.3
          ? Color.urgent : root.foreground
      }

      StatBar {
        width: (parent.width - Style.space(10)) / 2
        label: root.arena ? root.t("enemy." + root.arena.enemy.kind + ".name") : ""
        valueText: root.arena ? String(root.arena.enemyHp) : ""
        fraction: root.arena && root.arena.enemy.hpMax > 0
          ? root.arena.enemyHp / root.arena.enemy.hpMax : 0
        foreground: root.foreground
        fontFamily: root.fontFamily
        fill: Qt.darker(root.foreground, 1.6)
      }
    }

    PanelSeparator { width: parent.width }

    // ---- The log: the last four exchanges, oldest at the top.
    Column {
      width: parent.width
      spacing: Style.space(1)

      Repeater {
        model: root.arena ? root.arena.log : []

        Text {
          required property var modelData
          required property int index

          width: fight.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: root.logLine(modelData)
          // The newest line is the one being read.
          color: index === (root.arena ? root.arena.log.length - 1 : 0)
            ? root.foreground : Qt.darker(root.foreground, 1.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
        }
      }
    }

    // ---- The outcome, once there is one, and what it cost.
    Column {
      width: parent.width
      spacing: Style.space(2)
      visible: !!root.arena && root.arena.outcome !== "ongoing"

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: root.arena
          ? (root.arena.outcome === "won" ? root.t("arena.won") : root.t("arena.lost"))
          : ""
        color: root.arena && root.arena.outcome === "won" ? Color.accent : Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
      }

      // What a win brought, named rather than left to be noticed.
      Text {
        width: parent.width
        visible: !!root.arena && root.arena.outcome === "won" && root.lootLine !== ""
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: root.lootLine
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        renderType: Text.NativeRendering
      }

      // The price, in full, on the screen where it was paid.
      Text {
        width: parent.width
        visible: !!root.arena && Rules.num(root.arena.xpLost) > 0
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: root.arena ? root.t("arena.lost_xp", { xp: Rules.num(root.arena.xpLost) }) : ""
        color: Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        renderType: Text.NativeRendering
      }

      Text {
        width: parent.width
        visible: !!root.arena && root.arena.outcome === "lost"
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: root.t("arena.lost_kept")
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }
    }

    // ---- Four buttons, and nothing on a timer.
    Row {
      width: parent.width
      spacing: Style.space(4)
      visible: !!root.arena && root.arena.outcome === "ongoing"

      Button {
        text: root.t("arena.attack")
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        bordered: true
        onClicked: if (root.game) root.game.dispatch({ type: "fight_action", action: "attack" })
      }

      Button {
        text: root.game && root.hero
          ? root.t("skill." + Rules.CLASSES[root.hero.cls].skill.id + ".name") : ""
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        bordered: true
        enabled: !!root.arena && Rules.num(root.arena.cooldown) <= 0
        opacity: enabled ? 1 : 0.45
        tooltipText: root.arena && Rules.num(root.arena.cooldown) > 0
          ? root.t("arena.cooldown", { turns: Rules.num(root.arena.cooldown) }) : ""
        onClicked: if (root.game) root.game.dispatch({ type: "fight_action", action: "skill" })
      }

      Button {
        text: root.t("arena.defend")
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        bordered: true
        onClicked: if (root.game) root.game.dispatch({ type: "fight_action", action: "defend" })
      }

      // Drinking mid-fight is the whole reason to carry one, and hunting for
      // it in another tab while something is killing you is not a decision,
      // it is a chore.
      Button {
        visible: root.draughts > 0
        text: root.t("potion.drink") + " (" + root.draughts + ")"
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        bordered: true
        onClicked: if (root.game) root.game.dispatch({ type: "drink", potion: "healing_draught" })
      }

      Button {
        text: root.t("arena.flee")
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        onClicked: if (root.game) root.game.dispatch({ type: "flee" })
      }
    }

    Button {
      visible: !!root.arena && root.arena.outcome !== "ongoing"
      text: root.t("arena.done")
      foreground: root.foreground
      fontFamily: root.fontFamily
      bordered: true
      active: true
      onClicked: if (root.game) root.game.dispatch({ type: "flee" })
    }
  }
}
