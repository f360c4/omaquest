pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../game/Rules.js" as Rules

// Three steps to a hero: a name, a race, a class. Everything is a click; the
// only typing is the name, and it comes pre-filled.
//
// This replaces the tabs entirely until a hero exists, rather than sitting in
// one of them: there is nothing else to look at yet.
Item {
  id: root

  property var game: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  // Raised while the name field has focus, so Esc and the h/j/k/l cursor keys
  // go to the field instead of closing the panel or moving a selection.
  readonly property bool editing: nameField.activeFocus

  signal done()

  property int step: 0
  property string heroName: ""
  property string race: Rules.RACE_IDS[0]
  property string cls: Rules.CLASS_IDS[0]

  function t(key, vars) {
    return game ? game.t(key, vars) : key
  }

  function defaultName() {
    var user = String(Quickshell.env("USER") || "")
    if (!user) return "Hero"
    return user.charAt(0).toUpperCase() + user.slice(1)
  }

  function begin() {
    if (!game) return
    game.createHero(root.heroName || root.defaultName(), root.race, root.cls)
    root.done()
  }

  Component.onCompleted: {
    root.heroName = root.defaultName()
    nameField.text = root.heroName
  }

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.space(10)

    // ---- Step heading, and where in the three you are.
    Row {
      width: parent.width
      spacing: Style.space(8)

      PanelSectionHeader {
        text: root.t("onboarding.step" + root.step + ".title")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Item { width: 1; height: 1 }
    }

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: root.t("onboarding.step" + root.step + ".hint")
      color: Qt.darker(root.foreground, 1.3)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      renderType: Text.NativeRendering
    }

    // ---- Step 0: the name.
    TextField {
      id: nameField
      visible: root.step === 0
      width: parent.width
      foreground: root.foreground
      maximumLength: 24
      placeholderText: root.defaultName()
      onTextChanged: root.heroName = text
      onAccepted: root.step = 1
    }

    // ---- Steps 1 and 2: race, then class. Same grid, different list.
    Grid {
      visible: root.step > 0
      width: parent.width
      columns: 2
      spacing: Style.space(6)

      Repeater {
        model: root.step === 1 ? Rules.RACE_IDS : Rules.CLASS_IDS

        Button {
          id: card
          required property string modelData

          readonly property bool chosen: root.step === 1
            ? modelData === root.race
            : modelData === root.cls

          width: Math.floor((column.width - Style.space(6)) / 2)
          implicitHeight: Style.space(56)
          foreground: root.foreground
          fontFamily: root.fontFamily
          bordered: true
          selected: chosen
          leftAlign: true
          verticalPadding: Style.space(8)

          // The card carries its own two lines, so `text` stays empty and the
          // label below does the drawing.
          text: ""

          onClicked: {
            if (root.step === 1) root.race = modelData
            else root.cls = modelData
          }

          Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.spacing.controlPaddingX
            anchors.rightMargin: Style.spacing.controlPaddingX
            spacing: Style.space(8)

            // On the race step the sprite is the body alone; on the class step
            // it wears the class the card offers over the race already chosen,
            // so every one of the twenty-five combinations can be seen before
            // anything is committed to.
            PixelSprite {
              width: Style.space(48)
              height: Style.space(48)
              anchors.verticalCenter: parent.verticalCenter
              bank: root.game ? root.game.sprites : null
              body: root.step === 1 ? card.modelData : root.race
              overlay: root.step === 1 ? "" : card.modelData
              anim: card.chosen ? "cheer" : "idle"
              tint: root.foreground
              playing: root.visible
            }

            Column {
              width: parent.width - Style.space(48) - Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.t((root.step === 1 ? "race." : "class.") + card.modelData + ".name")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: card.chosen
                renderType: Text.NativeRendering
              }

              Text {
                width: parent.width
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: root.t((root.step === 1 ? "race." : "class.") + card.modelData + ".bonus")
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                renderType: Text.NativeRendering
              }
            }
          }
        }
      }
    }

    PanelSeparator { width: parent.width }

    // ---- What the machine turned out to be. Detected, never chosen: a
    //      desktop is a fortress and carries one more point of energy.
    Text {
      visible: root.step === 2
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: root.t("realm." + (root.game && root.game.realmType === "fortress" ? "fortress" : "caravan") + ".blurb")
      color: Qt.darker(root.foreground, 1.3)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }

    Row {
      width: parent.width
      spacing: Style.space(6)
      layoutDirection: Qt.RightToLeft

      Button {
        text: root.step < 2 ? root.t("ui.next") : root.t("ui.begin")
        foreground: root.foreground
        fontFamily: root.fontFamily
        bordered: true
        active: true
        onClicked: {
          if (root.step < 2) root.step += 1
          else root.begin()
        }
      }

      Button {
        visible: root.step > 0
        text: root.t("ui.back")
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.step -= 1
      }
    }
  }
}
