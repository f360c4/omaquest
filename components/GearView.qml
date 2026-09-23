pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "../game/Rules.js" as Rules

// Your attributes, what they add up to, and what you are wearing — in one
// place, because they are one question.
//
// It has its own tab rather than sitting under the hero card: equipping
// something and then hunting for the number it changed is the thing this is
// supposed to fix. Here the attribute, the total it feeds, and the item that
// moves it are all on the same screen.
//
// Every option shows its difference against what is worn **right now** — not
// its own stats, the delta. "+2 attack, -1 defence" is the decision; "+4
// damage" is a fact you then have to do arithmetic on.
Item {
  id: root

  property var game: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property int revision: game ? game.revision : 0
  readonly property var hero: { revision; return game ? game.hero() : null }

  // Which slot is open. Only one at a time, so the sheet does not turn into a
  // wall of every item for every slot.
  property string openSlot: ""

  function t(key, vars) {
    return game ? game.t(key, vars) : key
  }

  function wornIn(slot) {
    return root.hero && root.hero.equipment ? (root.hero.equipment[slot] || "") : ""
  }

  // What the chest holds that fits this slot.
  function optionsFor(slot) {
    if (!root.hero) return []
    var out = []
    for (var i = 0; i < root.hero.chest.length; i++) {
      var recipe = Rules.recipeById(root.hero.chest[i])
      if (recipe && recipe.slot === slot) out.push(recipe.id)
    }
    return out
  }

  // The difference wearing `id` would make, against what is in that slot now.
  // Computed by building the hero both ways and subtracting, so it can never
  // disagree with what actually happens on the click.
  function deltaFor(id) {
    if (!root.hero) return ""

    var recipe = Rules.recipeById(id)
    if (!recipe) return ""

    var before = Rules.cloneHero(root.hero)
    var after = Rules.cloneHero(root.hero)
    after.equipment[recipe.slot] = id

    var parts = []

    function note(label, a, b, suffix) {
      var difference = b - a
      if (difference === 0) return
      parts.push((difference > 0 ? "+" : "") + difference + " " + label + (suffix || ""))
    }

    note(root.t("ui.attack"), Rules.attackValue(before), Rules.attackValue(after))
    note(root.t("ui.defence"), Rules.defenseValue(before), Rules.defenseValue(after))
    note(root.t("ui.health"), Rules.hpMax(before), Rules.hpMax(after))

    for (var i = 0; i < Rules.ATTRS.length; i++) {
      var attr = Rules.ATTRS[i]
      note(root.t("attr." + attr),
        Rules.num(Rules.effectiveAttrs(before)[attr]),
        Rules.num(Rules.effectiveAttrs(after)[attr]))
    }

    var goldBefore = Math.round(Rules.num(Rules.equipmentStats(before).goldBonus) * 100)
    var goldAfter = Math.round(Rules.num(Rules.equipmentStats(after).goldBonus) * 100)
    note(root.t("ui.gold_short"), goldBefore, goldAfter, "%")

    return parts.length ? parts.join(" · ") : root.t("ui.gear_delta_none")
  }

  implicitHeight: column.implicitHeight

  // What the arena actually reads. Defence is in here rather than among the
  // attributes because it is not one: it comes from armour and nothing else.
  readonly property var derived: {
    revision
    if (!hero) return []
    var attrs = Rules.effectiveAttrs(hero)
    return [
      { label: t("ui.attack"), value: String(Rules.attackValue(hero)), note: "" },
      { label: t("ui.defence"), value: String(Rules.defenseValue(hero)), note: t("ui.defence_note") },
      { label: t("ui.crit"), value: Math.round(Rules.critChance(attrs) * 100) + "%", note: "" },
      { label: t("ui.skill_power"),
        value: "x" + (Math.round(Rules.skillPower(hero, attrs) * 100) / 100),
        note: t("skill." + Rules.CLASSES[hero.cls].skill.id + ".name") }
    ]
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(10)

    // ---- Attributes, each saying what it is currently doing. Five numbers
    //      with no explanation is the shape of the question "so what does
    //      Wisdom do for a warrior?", and the honest answer — nothing — is
    //      better written down than left to be guessed at.
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
          height: attrText.implicitHeight + Style.space(2)

          readonly property bool isPrimary: root.hero
            && Rules.CLASSES[root.hero.cls]
            && Rules.CLASSES[root.hero.cls].primary === modelData

          readonly property int fromGear: root.hero ? Rules.attrFromGear(root.hero, modelData) : 0
          readonly property var readout: root.hero ? Rules.attrReadout(root.hero, modelData) : null

          Column {
            id: attrText
            anchors.left: parent.left
            anchors.right: attrValue.left
            anchors.rightMargin: Style.space(8)
            spacing: 0

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.t("attr." + attrRow.modelData)
              color: attrRow.isPrimary ? Color.accent : Qt.darker(root.foreground, 1.2)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              renderType: Text.NativeRendering
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: attrRow.readout
                ? root.t("attr.effect." + attrRow.readout.key, { value: attrRow.readout.value })
                : ""
              color: Qt.darker(root.foreground, 1.8)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              renderType: Text.NativeRendering
            }
          }

          // The base, and what gear added, kept apart — a 16 nobody can
          // account for is worse than a 14 with a +2 beside it.
          Text {
            id: attrValue
            anchors.right: parent.right
            anchors.top: parent.top
            textFormat: Text.PlainText
            text: {
              if (!root.hero || !root.hero.attrs) return "-"
              var base = Rules.num(root.hero.attrs[attrRow.modelData])
              return attrRow.fromGear > 0 ? base + " +" + attrRow.fromGear : String(base)
            }
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: attrRow.isPrimary
            renderType: Text.NativeRendering
          }
        }
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: root.t("attr.primary_note")
        color: Qt.darker(root.foreground, 1.9)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }
    }

    PanelSeparator { width: parent.width }

    // ---- The numbers the fight actually uses, including the one that is not
    //      an attribute at all: defence comes from armour and nowhere else,
    //      which is why it is here rather than up there.
    Column {
      width: parent.width
      spacing: Style.space(2)

      PanelSectionHeader {
        text: root.t("ui.derived")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Repeater {
        model: root.derived

        Item {
          id: derivedRow
          required property var modelData

          width: column.width
          height: derivedLabel.implicitHeight

          Text {
            id: derivedLabel
            anchors.left: parent.left
            textFormat: Text.PlainText
            text: modelData.label + (modelData.note ? "  (" + modelData.note + ")" : "")
            color: Qt.darker(root.foreground, 1.3)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            renderType: Text.NativeRendering
          }

          Text {
            anchors.right: parent.right
            textFormat: Text.PlainText
            text: derivedRow.modelData.value
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            renderType: Text.NativeRendering
          }
        }
      }
    }

    PanelSeparator { width: parent.width }


    PanelSectionHeader {
      text: root.t("ui.gear")
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Repeater {
      model: Rules.SLOTS

      Column {
        id: slotBlock
        required property string modelData

        readonly property string worn: root.wornIn(modelData)
        readonly property var options: { root.revision; return root.optionsFor(modelData) }
        readonly property bool open: root.openSlot === modelData

        width: column.width
        spacing: Style.space(2)

        // ---- The slot itself: what is in it, and a way in.
        Item {
          width: parent.width
          height: Style.space(30)

          Column {
            anchors.left: parent.left
            anchors.right: changeButton.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.t("slot." + slotBlock.modelData)
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              renderType: Text.NativeRendering
            }

            Text {
              width: parent.width
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: slotBlock.worn
                ? root.t("item." + slotBlock.worn + ".name")
                : root.t("ui.gear_empty")
              color: slotBlock.worn ? root.foreground : Qt.darker(root.foreground, 2.0)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              renderType: Text.NativeRendering
            }
          }

          Button {
            id: changeButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: slotBlock.open ? "—" : root.t("ui.gear_wear")
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            selected: slotBlock.open
            onClicked: root.openSlot = slotBlock.open ? "" : slotBlock.modelData
          }
        }

        // ---- What you could put in it, each with what it would change.
        Column {
          width: parent.width
          spacing: Style.space(2)
          visible: slotBlock.open

          Text {
            width: parent.width
            visible: slotBlock.options.length === 0
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.t("ui.gear_none_for_slot")
            color: Qt.darker(root.foreground, 1.7)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            renderType: Text.NativeRendering
          }

          Repeater {
            model: slotBlock.options

            Item {
              id: option
              required property string modelData

              width: slotBlock.width
              height: Math.max(Style.space(30), optionText.implicitHeight + Style.space(6))

              Column {
                id: optionText
                anchors.left: parent.left
                anchors.right: wearButton.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(1)

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.t("item." + option.modelData + ".name")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  renderType: Text.NativeRendering
                }

                Text {
                  width: parent.width
                  wrapMode: Text.WordWrap
                  textFormat: Text.PlainText
                  text: root.deltaFor(option.modelData)
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  renderType: Text.NativeRendering
                }
              }

              Button {
                id: wearButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.t("ui.gear_wear")
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                bordered: true
                onClicked: {
                  if (root.game) root.game.dispatch({ type: "equip", item: option.modelData })
                  root.openSlot = ""
                }
              }
            }
          }

          // ---- Selling, where the thing being sold is in front of you. It is
          //      the same list, so nothing has to be found twice.
          Repeater {
            model: slotBlock.options

            Item {
              id: sellRow
              required property string modelData

              width: slotBlock.width
              height: Style.space(24)

              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.t("item." + sellRow.modelData + ".name")
                color: Qt.darker(root.foreground, 1.6)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                renderType: Text.NativeRendering
              }

              Button {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.t("forge.sell", { gold: Rules.itemValue(Rules.recipeById(sellRow.modelData)) })
                foreground: Qt.darker(root.foreground, 1.3)
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                onClicked: if (root.game) root.game.dispatch({ type: "sell_item", item: sellRow.modelData })
              }
            }
          }
        }
      }
    }

    // ---- Taking something off, which has to be possible or a slot is a
    //      one-way door.
    Button {
      visible: !!root.hero && root.openSlot !== "" && root.wornIn(root.openSlot) !== ""
      text: root.t("ui.gear_take_off")
      foreground: Qt.darker(root.foreground, 1.3)
      fontFamily: root.fontFamily
      fontSize: Style.font.caption
      onClicked: {
        if (root.game) root.game.dispatch({ type: "unequip", slot: root.openSlot })
        root.openSlot = ""
      }
    }
  }
}
