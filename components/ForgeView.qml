pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "../game/Rules.js" as Rules

// What you have, what you can make of it, and what is in the chest.
//
// A recipe you cannot afford is shown dimmed with its cost rather than hidden:
// the point of the forge is knowing what to go and look for.
Item {
  id: root

  property var game: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property int revision: game ? game.revision : 0
  readonly property var hero: { revision; return game ? game.hero() : null }
  readonly property var world: { revision; return game ? game.world : null }

  readonly property var stock: {
    revision
    if (!world || !world.day) return []
    return Rules.merchantStock(world.day.date)
  }

  function t(key, vars) {
    return game ? game.t(key, vars) : key
  }

  function costLine(recipe) {
    if (!root.hero) return ""
    var cost = Rules.costFor(root.hero, recipe)
    var parts = []
    for (var key in cost) parts.push(root.t("material." + key) + " ×" + cost[key])
    return parts.join(" · ")
  }

  function statLine(recipe) {
    var parts = []
    for (var key in recipe.stats) {
      var value = recipe.stats[key]
      if (key === "goldBonus" || key === "xpBonus")
        parts.push(root.t("forge.stat_" + key, { percent: Math.round(value * 100) }))
      else
        parts.push(root.t("forge.stat_" + key, { value: value > 0 ? "+" + value : String(value) }))
    }
    return parts.join(" · ")
  }

  function affordable(recipe) {
    return !!root.hero && Rules.canCraft(root.hero, recipe)
  }

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.space(10)

    // ---- What is in the pack. All six, including the empty ones, because a
    //      zero is the information you came for.
    Column {
      width: parent.width
      spacing: Style.space(3)

      Item {
        width: parent.width
        height: materialsHeader.implicitHeight

        PanelSectionHeader {
          id: materialsHeader
          text: root.t("forge.materials")
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Text {
          anchors.right: parent.right
          anchors.baseline: materialsHeader.baseline
          textFormat: Text.PlainText
          text: root.t("ui.gold", { gold: root.hero ? root.hero.gold : 0 })
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
        }
      }

      Flow {
        width: parent.width
        spacing: Style.space(8)

        Repeater {
          model: Rules.MATERIALS

          Text {
            required property string modelData
            textFormat: Text.PlainText
            text: root.t("material." + modelData) + " "
              + (root.hero ? Rules.num(root.hero.materials[modelData]) : 0)
            color: root.hero && Rules.num(root.hero.materials[modelData]) > 0
              ? root.foreground : Qt.darker(root.foreground, 2.0)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            renderType: Text.NativeRendering
          }
        }
      }
    }

    PanelSeparator { width: parent.width }

    // ---- Somebody passing through, placed right under the pack because that
    //      is what he is about: three things today, the same three all day,
    //      and he will take the old gear off your hands. Nine recipes between
    //      the materials and the man selling them is nine recipes of
    //      scrolling to answer "can I just buy the iron".
    Column {
      width: parent.width
      spacing: Style.space(4)

      PanelSectionHeader {
        text: root.t("forge.merchant")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Repeater {
        model: root.stock

        Item {
          id: offerRow
          required property var modelData

          readonly property bool affordable: !!root.hero
            && Rules.num(root.hero.gold) >= modelData.gold

          width: column.width
          height: Style.space(28)
          opacity: affordable ? 1 : 0.5

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.t("material." + offerRow.modelData.material)
              + " ×" + offerRow.modelData.count
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            renderType: Text.NativeRendering
          }

          Button {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.t("forge.buy", { gold: offerRow.modelData.gold })
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            enabled: offerRow.affordable
            opacity: enabled ? 1 : 0.45
            onClicked: if (root.game)
              root.game.dispatch({ type: "buy_material", offer: offerRow.modelData.id })
          }
        }
      }
    }

    PanelSeparator { width: parent.width }

    PanelSeparator { width: parent.width }

    // ---- What can be made.
    Column {
      width: parent.width
      spacing: Style.space(4)

      PanelSectionHeader {
        text: root.t("forge.recipes")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Repeater {
        model: Rules.RECIPES

        Item {
          id: recipeRow
          required property var modelData

          readonly property bool canMake: root.affordable(modelData)
          readonly property bool worn: !!root.hero
            && root.hero.equipment[modelData.slot] === modelData.id

          width: column.width
          height: Math.max(Style.space(34), recipeContent.implicitHeight)
          opacity: canMake || worn ? 1 : 0.5

          Row {
            id: recipeContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Column {
              width: recipeContent.width - makeButton.width - Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.t("item." + recipeRow.modelData.id + ".name")
                  + (recipeRow.worn ? " · " + root.t("forge.worn") : "")
                color: recipeRow.worn ? Color.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                renderType: Text.NativeRendering
              }

              Text {
                width: parent.width
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: root.statLine(recipeRow.modelData) + "  —  " + root.costLine(recipeRow.modelData)
                color: Qt.darker(root.foreground, 1.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                renderType: Text.NativeRendering
              }
            }

            Button {
              id: makeButton
              anchors.verticalCenter: parent.verticalCenter
              text: root.t("forge.make")
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              enabled: recipeRow.canMake
              opacity: enabled ? 1 : 0.45
              onClicked: if (root.game)
                root.game.dispatch({ type: "craft", recipe: recipeRow.modelData.id })
            }
          }
        }
      }
    }

    // ---- The chest. Everything here can be put on, and putting something on
    //      puts whatever was there back, so nothing is ever lost to a choice.
    Column {
      width: parent.width
      spacing: Style.space(4)

      PanelSectionHeader {
        text: root.t("forge.chest")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Text {
        width: parent.width
        visible: !root.hero || root.hero.chest.length === 0
        textFormat: Text.PlainText
        text: root.t("forge.chest_empty")
        color: Qt.darker(root.foreground, 1.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }

      Repeater {
        model: root.hero ? root.hero.chest : []

        Item {
          id: chestRow
          required property string modelData

          width: column.width
          height: Style.space(28)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.t("item." + chestRow.modelData + ".name")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            renderType: Text.NativeRendering
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Button {
              text: root.t("forge.equip")
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onClicked: if (root.game) root.game.dispatch({ type: "equip", item: chestRow.modelData })
            }

            Button {
              text: root.t("forge.sell", {
                gold: Rules.itemValue(Rules.recipeById(chestRow.modelData))
              })
              foreground: Qt.darker(root.foreground, 1.3)
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onClicked: if (root.game) root.game.dispatch({ type: "sell_item", item: chestRow.modelData })
            }
          }
        }
      }
    }
  }
}
