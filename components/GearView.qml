pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "../game/Rules.js" as Rules

// What the hero is carrying: the three slots, everything that fits them, and
// what is in the pack to drink.
//
// The attributes live on the Hero sheet, where they describe the hero. This is
// the inventory — what you own and what you can do with it.
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

  // Everything that fits this slot, worn or not. What is on goes first and is
  // marked: a list of alternatives that leaves out the thing you are wearing
  // is a list you cannot compare against.
  function optionsFor(slot) {
    if (!root.hero) return []
    var out = []
    var worn = root.wornIn(slot)
    if (worn) out.push(worn)
    for (var i = 0; i < root.hero.chest.length; i++) {
      var recipe = Rules.recipeById(root.hero.chest[i])
      if (recipe && recipe.slot === slot && out.indexOf(recipe.id) === -1) out.push(recipe.id)
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

  Column {
    id: column
    width: parent.width
    spacing: Style.space(10)

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

              readonly property bool worn: slotBlock.worn === modelData

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
                  // Said next to the item rather than only at the top of the
                  // slot, because the list is where the comparison happens.
                  text: root.t("item." + option.modelData + ".name")
                    + (option.worn ? "  " + root.t("ui.gear_equipped") : "")
                  color: option.worn ? Color.accent : root.foreground
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
                visible: !option.worn
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

              // Never what is on the hero: taking it off is one click and
              // stops a misclick selling the sword you are holding.
              readonly property bool sellable: slotBlock.worn !== modelData

              width: slotBlock.width
              height: sellable ? Style.space(24) : 0
              visible: sellable

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

    PanelSeparator { width: parent.width }

    // ---- What there is to drink. A potion is the decision you make in the
    //      middle of something going wrong, which is why it is here beside
    //      the gear rather than back in the shop.
    Column {
      width: parent.width
      spacing: Style.space(3)

      PanelSectionHeader {
        text: root.t("ui.pack")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Repeater {
        model: Rules.POTIONS

        Item {
          id: potionRow
          required property string modelData

          readonly property int held: root.hero ? Rules.num(root.hero.potions[modelData]) : 0

          width: column.width
          height: Math.max(Style.space(30), potionText.implicitHeight + Style.space(6))
          opacity: held > 0 ? 1 : 0.5

          Column {
            id: potionText
            anchors.left: parent.left
            anchors.right: drinkButton.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.t("potion." + potionRow.modelData + ".name") + "  " + potionRow.held
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              renderType: Text.NativeRendering
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: root.t("potion." + potionRow.modelData + ".note")
              color: Qt.darker(root.foreground, 1.6)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              renderType: Text.NativeRendering
            }
          }

          Button {
            id: drinkButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.t("potion.drink")
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            enabled: potionRow.held > 0
            opacity: enabled ? 1 : 0.45
            onClicked: if (root.game) root.game.dispatch({ type: "drink", potion: potionRow.modelData })
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
