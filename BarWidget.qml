pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "components"

// The hero's slot in the bar, and the host for the game panel.
//
// The bar mounts one of these per monitor. State lives in Service.qml, which
// is mounted once; this widget only draws it and routes clicks. Left click
// opens the panel, right click opens it on the Chronicle.
BarWidget {
  id: root
  moduleName: "f360c4.omaquest"

  // Third-party plugins reach their own service and nothing else. Guarded
  // because the bar-widget contract instantiates this bare, before injection.
  readonly property var game: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null
  readonly property bool serviceReady: !!game && game.initialized === true

  // Nerd Font glyphs are spelled by code point, never pasted: agent editing
  // tools mangle multibyte characters, and a mangled glyph is a tofu box in
  // everyone's bar. nf-md-sword — the stand-in while the service comes up or
  // before there is a hero to draw.
  readonly property string heroGlyph: String.fromCodePoint(0xF04E5)

  readonly property int revision: game ? game.revision : 0
  readonly property var hero: { revision; return serviceReady ? game.hero() : null }
  readonly property bool hasHero: !!hero

  // The hero's level beside the sprite, off by default and never on a vertical
  // bar, where a widget has one icon slot and no room for a label.
  readonly property bool showLevel: setting("showLevel", false) === true && !vertical && hasHero

  readonly property string tooltip: {
    if (!hasHero) return "Omaquest"
    return game.t("ui.tooltip", {
      name: hero.name, level: hero.level,
      cls: game.t("class." + hero.cls + ".name"),
      hp: hero.hp, hpMax: hero.hpMax,
      energy: hero.energy, energyMax: hero.energyMax
    })
  }

  // ---- Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the bar-widget
  //      root, and the popout coordinator prefers closeForPopoutSwitch.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open(payload) {
    if (panelLoader.item) panelLoader.item.open(payload)
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("game" in target) target.game = root.game
  }

  // The service answers to the same inline entry the panel writes to, so the
  // language and the toggles are one value rather than two that drift.
  function pushSettings() {
    if (root.game && typeof root.game.applySettings === "function")
      root.game.applySettings(root.settings)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: { injectPanel(); pushSettings() }
  onGameChanged: { injectPanel(); pushSettings() }
  Component.onCompleted: pushSettings()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "f360c4.omaquest"

    function open(payload: string): void { root.open(payload) }
    function close(): void { root.close() }
    function show(): void { root.open("") }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }

    // Ask the Bard without opening the panel, so it can sit on a keybind.
    // Refused, silently, if it is switched off, `omarchy` is not installed,
    // or one was asked for in the last minute.
    function bard(): void {
      if (root.game && typeof root.game.askTheBard === "function") root.game.askTheBard()
    }

    // Send the hero for a walk without opening the panel, so it can sit on a
    // keybind. Refused, silently, when the hero is busy or has already had
    // their three today — the same rule the button follows.
    function stroll(): void {
      if (root.game && typeof root.game.startStroll === "function") root.game.startStroll()
    }

    // Open on a named tab, which is how a notification's click can land on
    // the thing it was about.
    function tab(name: string): void {
      if (panelLoader.item) {
        panelLoader.item.showTab(name)
        panelLoader.item.open("")
      }
    }

    // `omarchy-shell f360c4.omaquest status` — levels and counts, the same
    // things the panel shows, so a script or a bug report can read the hero
    // without a screenshot.
    function status(): string {
      return JSON.stringify(root.game && typeof root.game.publicStatus === "function"
        ? root.game.publicStatus()
        : { ready: false, reason: "service not mounted" })
    }
  }

  // BarIconButton owns the icon slot and the optical centering every other
  // icon widget in the bar gets. Phase 2 swaps `text` for an `iconComponent`
  // carrying the hero sprite; the slot geometry stays exactly the same.
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // The glyph only shows while there is no hero; once there is one, the
    // iconComponent takes the slot and `text` is left empty.
    text: root.hasHero ? "" : root.heroGlyph
    dimmed: !root.serviceReady
    tooltipText: root.tooltip
    slotSize: root.showLevel
      ? Style.bar.iconSlot + Math.ceil(levelMetrics.width) + Style.space(3)
      : Style.bar.iconSlot

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        // Straight to the chronicle: it is the one tab you open to read rather
        // than to do something.
        if (panelLoader.item) {
          panelLoader.item.showTab("chronicle")
          if (!root.opened) panelLoader.item.open("")
        }
        return
      }
      if (buttonCode === Qt.LeftButton) root.togglePanel()
    }

    TextMetrics {
      id: levelMetrics
      font.family: button.fontFamily
      font.pixelSize: Style.font.caption
      text: root.hasHero ? "Lv " + root.hero.level : ""
    }

    // Sits over the icon slot rather than in it: BarIconButton centres its
    // own canvas, and the level reads as a suffix to the sprite.
    Text {
      visible: root.showLevel
      anchors.right: parent.right
      anchors.rightMargin: Style.space(2)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: levelMetrics.text
      color: button.foreground
      font.family: button.fontFamily
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }

    iconComponent: root.hasHero ? heroSprite : null

    Component {
      id: heroSprite

      PixelSprite {
        bank: root.game ? root.game.sprites : null
        body: root.hero ? root.hero.race : ""
        overlay: root.hero ? root.hero.cls : ""
        anim: root.game ? root.game.heroAnim : "idle"
        tint: button.foreground
        // The bar is always mounted, so an off-screen or concealed widget
        // must stop animating rather than repaint forever for nobody.
        playing: button.visible && !button.concealed
      }
    }
  }
}
