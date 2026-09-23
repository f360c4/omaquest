pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "../game/Rules.js" as Rules
import "../game/World.js" as World

// Everything the player can change, and everything the plugin reads.
//
// The reading list is in here rather than only in the README because a plugin
// that runs unsandboxed inside someone's shell owes them that answer where
// they are, not in a file on a website.
Item {
  id: root

  property var game: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  // Written back to the widget's own inline entry in shell.json, through the
  // shell's API. Panel.qml owns the write because it has the bar.
  signal settingChanged(string key, var value)

  // Which calling the dialog is currently asking about.
  property string pendingClass: ""

  readonly property int revision: game ? game.revision : 0
  readonly property var hero: { revision; return game ? game.hero() : null }
  readonly property var world: { revision; return game ? game.world : null }

  // Raised while a text field has focus, so Esc and the cursor keys go to the
  // field rather than to the panel.
  readonly property bool editing: realmField.activeFocus || gitField.activeFocus

  function t(key, vars) {
    return game ? game.t(key, vars) : key
  }

  function setting(key, fallback) {
    return game ? game.setting(key, fallback) : fallback
  }

  readonly property var toggles: [
    { key: "showLevel", fallback: false },
    { key: "notifyLevelUp", fallback: true },
    { key: "notifyBoss", fallback: true },
    { key: "notifyExpedition", fallback: false },
    { key: "notifyQuests", fallback: false }
  ]

  readonly property var arcaneToggles: [
    { key: "sensorAgents", fallback: false },
    { key: "sensorGit", fallback: false }
  ]

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.space(12)

    // ---- Language.
    Column {
      width: parent.width
      spacing: Style.space(4)

      PanelSectionHeader {
        text: root.t("settings.language")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Row {
        spacing: Style.space(4)

        Repeater {
          model: ["auto", "en", "pt-BR"]

          Button {
            required property string modelData
            text: root.t("settings.language_" + modelData.replace("-", "_"))
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            selected: root.setting("language", "auto") === modelData
            onClicked: root.settingChanged("language", modelData)
          }
        }
      }
    }

    // ---- Sound. Off by default, because a bar widget that makes a noise
    //      nobody asked for is a bar widget people uninstall.
    Column {
      width: parent.width
      spacing: Style.space(4)

      PanelSectionHeader {
        text: root.t("settings.sound")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: root.t("settings.sound_note")
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }

      Row {
        spacing: Style.space(4)

        Repeater {
          model: ["off", "quiet", "full"]

          Button {
            required property string modelData
            text: root.t("settings.sound_" + modelData)
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            selected: root.setting("sound", "off") === modelData
            onClicked: root.settingChanged("sound", modelData)
          }
        }
      }
    }

    PanelSeparator { width: parent.width }

    // ---- The bar, and being told things.
    Column {
      width: parent.width
      spacing: Style.space(6)

      PanelSectionHeader {
        text: root.t("settings.notifications")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: root.t("settings.notifications_note")
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }

      Repeater {
        model: root.toggles

        Item {
          id: toggleRow
          required property var modelData

          width: column.width
          height: Math.max(toggleLabel.implicitHeight, toggleSwitch.implicitHeight)

          Text {
            id: toggleLabel
            anchors.left: parent.left
            anchors.right: toggleSwitch.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.t("settings." + toggleRow.modelData.key)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            renderType: Text.NativeRendering
          }

          ToggleSwitch {
            id: toggleSwitch
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: root.setting(toggleRow.modelData.key, toggleRow.modelData.fallback) === true
            onToggled: root.settingChanged(toggleRow.modelData.key, !checked)
          }
        }
      }
    }

    PanelSeparator { width: parent.width }

    // ---- The two sensors that are nobody's business by default.
    Column {
      width: parent.width
      spacing: Style.space(6)

      PanelSectionHeader {
        text: root.t("settings.arcane")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Repeater {
        model: root.arcaneToggles

        Item {
          id: arcaneRow
          required property var modelData

          width: column.width
          height: arcaneText.implicitHeight

          Column {
            id: arcaneText
            anchors.left: parent.left
            anchors.right: arcaneSwitch.left
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(1)

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: root.t("settings." + arcaneRow.modelData.key)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              renderType: Text.NativeRendering
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: root.t("settings." + arcaneRow.modelData.key + "_note")
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              renderType: Text.NativeRendering
            }

            // A switch that is on and doing nothing has to say why. This one
            // reads files somebody else writes, and if nobody is writing them
            // it reads the same number for ever.
            Text {
              width: parent.width
              visible: arcaneRow.modelData.key === "sensorAgents"
                && !!root.game && root.game.agentDataStale
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: root.t("settings.sensorAgents_stale")
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              renderType: Text.NativeRendering
            }
          }

          ToggleSwitch {
            id: arcaneSwitch
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: root.setting(arcaneRow.modelData.key, false) === true
            onToggled: root.settingChanged(arcaneRow.modelData.key, !checked)
          }
        }
      }
    }

    // Where to look, shown only when there is any point in asking.
    Column {
      width: parent.width
      spacing: Style.space(4)
      visible: root.setting("sensorGit", false) === true

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: root.t("settings.gitPath")
        color: Qt.darker(root.foreground, 1.2)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        renderType: Text.NativeRendering
      }

      Row {
        width: parent.width
        spacing: Style.space(6)

        TextField {
          id: gitField
          width: parent.width - saveGitPath.width - Style.space(6)
          foreground: root.foreground
          maximumLength: 200
          text: String(root.setting("gitPath", "~/Work"))
          onAccepted: root.settingChanged("gitPath", text)
        }

        Button {
          id: saveGitPath
          text: root.t("settings.rename")
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          bordered: true
          onClicked: root.settingChanged("gitPath", gitField.text)
        }
      }
    }

    PanelSeparator { width: parent.width }

    // ---- The Bard. Hidden entirely when `omarchy` is not installed, because
    //      a switch that cannot do anything is worse than no switch.
    Column {
      width: parent.width
      spacing: Style.space(4)
      visible: !!root.game && root.game.bardAvailable

      Item {
        width: parent.width
        height: bardText.implicitHeight

        Column {
          id: bardText
          anchors.left: parent.left
          anchors.right: bardSwitch.left
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(1)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.t("settings.bard")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            renderType: Text.NativeRendering
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.t("settings.bard_note")
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            renderType: Text.NativeRendering
          }
        }

        ToggleSwitch {
          id: bardSwitch
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          checked: root.setting("bardEnabled", false) === true
          onToggled: root.settingChanged("bardEnabled", !checked)
        }
      }
    }

    PanelSeparator { width: parent.width }

    // ---- The realm's name. Local, and shown to nobody.
    Column {
      width: parent.width
      spacing: Style.space(4)

      PanelSectionHeader {
        text: root.t("settings.realm_name")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Row {
        width: parent.width
        spacing: Style.space(6)

        TextField {
          id: realmField
          width: parent.width - saveRealm.width - Style.space(6)
          foreground: root.foreground
          maximumLength: 32
          text: root.world && root.world.realm ? root.world.realm.name : ""
          onAccepted: if (root.game) root.game.dispatch({ type: "set_realm_name", name: text })
        }

        Button {
          id: saveRealm
          text: root.t("settings.rename")
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          bordered: true
          onClicked: if (root.game) root.game.dispatch({ type: "set_realm_name", name: realmField.text })
        }
      }
    }

    PanelSeparator { width: parent.width }

    // ---- Changing calling, and starting over.
    Column {
      width: parent.width
      spacing: Style.space(6)

      PanelSectionHeader {
        text: root.t("settings.calling")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: root.t("settings.calling_note", { gold: World.CLASS_CHANGE_GOLD })
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }

      Flow {
        width: parent.width
        spacing: Style.space(4)

        Repeater {
          model: Rules.CLASS_IDS

          Button {
            id: classButton
            required property string modelData

            readonly property bool current: !!root.hero && root.hero.cls === modelData
            readonly property bool affordable: !!root.hero
              && Rules.num(root.hero.gold) >= World.CLASS_CHANGE_GOLD

            text: root.t("class." + modelData + ".name")
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            selected: current
            enabled: !current && affordable
            opacity: enabled || current ? 1 : 0.45
            // Asked first. This is the one button in the plugin that spends
            // gold and cannot be undone, and it sat one misclick away from
            // doing both silently while starting over — which costs nothing —
            // had a dialog in front of it.
            onClicked: {
              root.pendingClass = modelData
              classDialog.opened = true
            }
          }
        }
      }

      Button {
        text: root.t("settings.rebirth")
        foreground: Color.urgent
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        bordered: true
        onClicked: rebirthDialog.opened = true
      }
    }

    PanelSeparator { width: parent.width }

    // ---- What this plugin reads. Kept in the panel, in the player's own
    //      language, and written from the same list the README carries.
    Column {
      width: parent.width
      spacing: Style.space(4)

      PanelSectionHeader {
        text: root.t("settings.what_it_reads")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: root.t("settings.what_it_reads_body")
        color: Qt.darker(root.foreground, 1.3)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.t("settings.version", { version: root.game ? root.game.version : "" })
        color: Qt.darker(root.foreground, 1.8)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }
    }
  }

  // Starting over is the one thing in the plugin that cannot be undone by
  // clicking again, so it is the one thing that asks.
  ConfirmDialog {
    id: classDialog
    message: root.t("settings.calling_confirm", {
      cls: root.pendingClass ? root.t("class." + root.pendingClass + ".name") : "",
      gold: World.CLASS_CHANGE_GOLD
    })
    cancelText: root.t("settings.cancel")
    confirmText: root.t("settings.calling_change")
    foreground: root.foreground
    fontFamily: root.fontFamily
    onConfirmed: {
      classDialog.opened = false
      if (root.game && root.pendingClass)
        root.game.dispatch({ type: "change_class", cls: root.pendingClass })
      root.pendingClass = ""
    }
    onCanceled: {
      classDialog.opened = false
      root.pendingClass = ""
    }
  }

  ConfirmDialog {
    id: rebirthDialog
    message: root.t("settings.rebirth_confirm")
    cancelText: root.t("settings.cancel")
    confirmText: root.t("settings.rebirth")
    foreground: root.foreground
    fontFamily: root.fontFamily
    onConfirmed: {
      rebirthDialog.opened = false
      if (root.game && root.hero)
        root.game.dispatch({ type: "rebirth", race: root.hero.race, cls: root.hero.cls })
    }
    onCanceled: rebirthDialog.opened = false
  }
}
