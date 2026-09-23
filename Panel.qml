pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "components"

// The game panel. BarWidget.qml owns the bar slot and hands this panel the
// button to anchor against, plus the one service instance to read from.
//
// `manageIpc: false`: the widget carries the IPC handler, because the bar
// tracks the widget mounted in its slot rather than this nested panel.
Panel {
  id: root
  moduleName: "f360c4.omaquest"
  manageIpc: false

  property var anchorItem: null

  // The bar identifies a panel by the widget in its slot: the popout
  // coordinator (and the open-panel dot under the pill) compares against
  // `slot.activeItem`, and switchPanelFrom looks the slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property var game: null
  readonly property bool serviceReady: !!game && game.initialized === true
  readonly property bool hasHero: !!game && game.hasHero === true

  readonly property int revision: game ? game.revision : 0

  // Which tab is open. `summon` can name one, so a notification can send the
  // player straight to the thing it was about.
  property string tab: "hero"

  // A tab is marked when something arrived there that has not been looked at.
  readonly property bool arenaUnseen: {
    revision
    if (!game || !game.world) return false
    var bosses = game.world.bosses || []
    for (var i = 0; i < bosses.length; i++) if (bosses[i].seen !== true) return true
    return false
  }

  readonly property bool expeditionUnseen: {
    revision
    if (!game || !game.world || !game.world.expedition) return false
    return game.world.expedition.resolved === true && game.world.expedition.seen !== true
  }

  readonly property var tabs: {
    revision
    // The chronicle sits second, right after the hero: it is the tab you open
    // to read rather than to do something, and it is the part that is still
    // interesting in month three. The three you act in follow, and settings
    // goes last because it is the one nobody opens twice.
    return [
      { id: "hero", label: root.t("ui.tab_hero"), marked: false },
      { id: "gear", label: root.t("ui.tab_gear"), marked: false },
      { id: "chronicle", label: root.t("ui.tab_chronicle"), marked: false },
      { id: "arena", label: root.t("ui.tab_arena"), marked: root.arenaUnseen },
      { id: "expedition", label: root.t("ui.tab_expedition"), marked: root.expeditionUnseen },
      { id: "forge", label: root.t("ui.tab_forge"), marked: false },
      { id: "settings", label: root.t("ui.tab_settings"), marked: false }
    ]
  }

  function showTab(name) {
    for (var i = 0; i < root.tabs.length; i++)
      if (root.tabs[i].id === name) { root.tab = name; return true }
    return false
  }

  // `summon` hands over the payload as a JSON string. Anything unrecognised is
  // accepted and ignored rather than refused.
  function open(payload) {
    // A fight left running is the thing the player came back for.
    if (game && game.world && game.world.arena) root.tab = "arena"

    if (payload) {
      try {
        var parsed = JSON.parse(String(payload))
        if (parsed && parsed.tab) root.showTab(String(parsed.tab))
      } catch (error) {
        // Not JSON, or not for us. Opening is still the right answer.
      }
    }
    root.controller.show()
  }

  // Guarded so the panel renders before the bar is injected; the bar-widget
  // contract instantiates it bare.
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  function t(key, vars) {
    return serviceReady ? game.t(key, vars) : ""
  }

  // Writes one key back to this widget's own inline entry in shell.json, the
  // only place outside its state directory the plugin ever writes — and only
  // ever its own entry, which is all the shell's API allows anyway.
  function persistSetting(key, value) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    entry[key] = value

    // Applied locally first, so the switch moves on the click rather than when
    // the write comes back round through the bar.
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // Closing forgets where you were. Coming back to the Forge because that is
  // where you happened to be three hours ago is not continuity, it is the
  // panel remembering something nobody asked it to — and the Hero sheet is
  // what somebody opening this wants to see.
  //
  // A fight in progress is the exception, and `open` puts that back.
  function close() {
    root.tab = "hero"
    root.controller.hide()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(Math.min(content.implicitHeight, Style.space(520)))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Typing a hero's name must not be read as panel navigation: h, j, k and
      // l are cursor keys here, and Esc would close the panel mid-word.
      blocked: (onboarding.item ? onboarding.item.editing === true : false)
        || (settingsView.item ? settingsView.item.editing === true : false)
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: content
          width: scroll.width
          spacing: Style.space(10)

          // Until there is a hero there is nothing else worth showing, so
          // onboarding takes the whole panel rather than sitting in a tab.
          Loader {
            id: onboarding
            width: parent.width
            active: root.serviceReady && !root.hasHero
            visible: active
            sourceComponent: OnboardingView {
              game: root.game
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }
          }

          TabBar {
            width: parent.width
            visible: root.serviceReady && root.hasHero
            tabs: root.tabs
            current: root.tab
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onSelected: function (id) {
              root.tab = id
              // Looking at the tab is what clears its dot.
              if (id === "expedition" && root.game) root.game.dispatch({ type: "mark_seen", what: "expedition" })
            }
          }

          Loader {
            id: heroSheet
            width: parent.width
            active: root.serviceReady && root.hasHero && root.tab === "hero"
            visible: active
            sourceComponent: HeroView {
              game: root.game
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }
          }

          Loader {
            id: arena
            width: parent.width
            // A fight in progress pins the tab: closing the panel mid-fight and
            // reopening it comes back to the same fight, not to the hero sheet.
            active: root.serviceReady && root.hasHero && root.tab === "arena"
            visible: active
            sourceComponent: ArenaView {
              game: root.game
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }
          }

          Loader {
            id: expedition
            width: parent.width
            active: root.serviceReady && root.hasHero && root.tab === "expedition"
            visible: active
            sourceComponent: ExpeditionView {
              game: root.game
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }
          }

          Loader {
            id: forge
            width: parent.width
            active: root.serviceReady && root.hasHero && root.tab === "forge"
            visible: active
            sourceComponent: ForgeView {
              game: root.game
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }
          }

          Loader {
            id: gear
            width: parent.width
            active: root.serviceReady && root.hasHero && root.tab === "gear"
            visible: active
            sourceComponent: GearView {
              game: root.game
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }
          }

          Loader {
            id: chronicle
            width: parent.width
            active: root.serviceReady && root.hasHero && root.tab === "chronicle"
            visible: active
            sourceComponent: ChronicleView {
              game: root.game
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }
          }

          Loader {
            id: settingsView
            width: parent.width
            active: root.serviceReady && root.hasHero && root.tab === "settings"
            visible: active
            sourceComponent: SettingsView {
              game: root.game
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onSettingChanged: function (key, value) { root.persistSetting(key, value) }
            }
          }

          Text {
            width: parent.width
            visible: !root.serviceReady
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.t("ui.loading")
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            renderType: Text.NativeRendering
          }
        }
      }
    }
  }
}
