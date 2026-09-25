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

  // Weapons are named for the calling holding them, so the name comes from the
  // service, which is the only thing that knows both the hero and the words.
  function itemName(id) {
    return game ? game.itemName(id) : String(id)
  }

  function wornIn(slot) {
    return root.hero && root.hero.equipment ? (root.hero.equipment[slot] || "") : ""
  }

  // How many of a thing is in the chest. The chest is a plain list with
  // repeats in it, and every view of it used to fold those away — two Iron
  // Swords looked exactly like one, right up until you sold one and the row
  // stayed.
  function countOf(id) {
    if (!root.hero || !root.hero.chest) return 0
    var n = 0
    for (var i = 0; i < root.hero.chest.length; i++)
      if (root.hero.chest[i] === id) n++
    return n
  }

  // A suffix, only when there is more than one. "×1" on every row is noise.
  function times(id) {
    var n = root.countOf(id)
    return n > 1 ? "  ×" + n : ""
  }

  // Everything in the chest, once per kind, in the order it was put there.
  function chestKinds() {
    if (!root.hero || !root.hero.chest) return []
    var out = []
    for (var i = 0; i < root.hero.chest.length; i++)
      if (out.indexOf(root.hero.chest[i]) === -1) out.push(root.hero.chest[i])
    return out
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
                ? root.itemName(slotBlock.worn)
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
                  text: root.itemName(option.modelData)
                    + (option.worn ? "  " + root.t("ui.gear_equipped") : root.times(option.modelData))
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

        }
      }
    }

    PanelSeparator { width: parent.width }

    // ---- The chest, and the only place anything is sold.
    //
    //      Selling used to live inside the slot disclosure, which meant it
    //      only existed after you had clicked "wear" on the right slot — so
    //      the answer to "where do I sell things" was three clicks deep in a
    //      panel that had no sign there was anything down there. It is a
    //      section now, with the counts on it.
    Column {
      width: parent.width
      spacing: Style.space(3)

      PanelSectionHeader {
        text: root.t("ui.chest")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Text {
        width: parent.width
        visible: root.chestKinds().length === 0
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: root.t("ui.chest_empty")
        color: Qt.darker(root.foreground, 1.7)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }

      Repeater {
        model: { root.revision; return root.chestKinds() }

        Item {
          id: chestRow
          required property string modelData

          readonly property var recipe: Rules.recipeById(modelData)

          width: column.width
          height: Math.max(Style.space(30), chestText.implicitHeight + Style.space(6))

          Column {
            id: chestText
            anchors.left: parent.left
            anchors.right: sellButton.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)

            Text {
              width: parent.width
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: root.itemName(chestRow.modelData) + root.times(chestRow.modelData)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              renderType: Text.NativeRendering
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: chestRow.recipe ? root.t("slot." + chestRow.recipe.slot) : ""
              color: Qt.darker(root.foreground, 1.6)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              renderType: Text.NativeRendering
            }
          }

          Button {
            id: sellButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.t("forge.sell", { gold: Rules.itemValue(chestRow.recipe) })
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            onClicked: if (root.game)
              root.game.dispatch({ type: "sell_item", item: chestRow.modelData })
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
              // Written the same way the chest writes it, because two ways of
              // saying "how many" on one screen is one way too many.
              text: root.t("potion." + potionRow.modelData + ".name")
                + (potionRow.held > 0 ? "  ×" + potionRow.held : "")
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
