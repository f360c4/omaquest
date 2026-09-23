pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons

// The hero, out for a walk across the bottom of the screen.
//
// This is the only thing the plugin ever draws outside its own panel, and it
// only exists because somebody clicked.
//
// It is a round trip, not a crossing: the hero walks out along the ground,
// does whatever their calling does at the far end, turns around and walks
// home. Walking off one side and never coming back reads as the sprite having
// escaped rather than having been for a walk.
//
// It does not climb anything, follow the pointer, or stay. Twenty-six seconds,
// along the floor, and it cannot take a click from what is underneath it.
//
// It is a layer-shell surface, which on Wayland is the only way to draw over
// the desktop at all — but it is not a window in any sense a user would
// recognise: no title bar, no taskbar entry, no focus, and click-through. The
// same thing Omagotchi's RoamWindow is.
//
// Declared once and shown by `visible`, never created on demand. Building a
// layer-shell surface at runtime leaks a zombie one on every plugin
// hot-reload, which then wedges screencopy — `grim` stops working on that
// output. Omagotchi's source says so in as many words, and
// `01-plataforma-omarchy.md` warns about it too.
PanelWindow {
  id: root

  property var game: null
  property real progress: 0
  property color tint: Color.foreground

  // Large enough to notice. At 48 across the bottom edge of a 1920-wide
  // screen the hero is genuinely easy to miss — which is what happened the
  // first time somebody other than the author went looking for it.
  readonly property int spriteSize: Style.space(64)

  // The output Hyprland has focused, which is the one being looked at. A hero
  // that strolls across the other monitor has not strolled, as far as anyone
  // watching is concerned. Falls back to the largest.
  screen: {
    var screens = Quickshell.screens
    var focused = Hyprland.focusedMonitor
    var wanted = focused ? String(focused.name || "") : ""
    var i

    if (wanted !== "")
      for (i = 0; i < screens.length; i++) if (screens[i].name === wanted) return screens[i]

    var best = null
    for (i = 0; i < screens.length; i++)
      if (!best || screens[i].width * screens[i].height > best.width * best.height) best = screens[i]
    return best
  }

  // `screensReady` is the service dropping visibility for a beat whenever the
  // output list changes — see the comment there.
  visible: !!game && game.strolling === true && game.screensReady === true

  anchors { left: true; right: true; bottom: true }
  implicitHeight: root.spriteSize + Style.space(16)
  color: "transparent"

  WlrLayershell.namespace: "omaquest-stroll"
  // Overlay: above everything, because the point of watching the hero walk is
  // watching the hero walk, and a layer that hides behind the window in front
  // defeats it. Safe to do because the input region below is empty — the hero
  // is painted over the desktop and cannot take a click from it.
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore

  // Nothing here is clickable, and an empty input region is what guarantees
  // the hero can never eat a click meant for the desktop underneath.
  mask: Region {}

  // The three legs of the trip. Out, a pause at the far end, and back.
  readonly property real outboundEnd: game ? game.strollTurnStart : 0.42
  readonly property real inboundStart: game ? game.strollTurnEnd : 0.58

  // How far along the outbound leg the hero gets. Not all the way across:
  // stopping short of the far edge is what makes it a walk rather than an
  // escape.
  readonly property real reach: 0.72

  PixelSprite {
    id: hero

    width: root.spriteSize
    height: root.spriteSize
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(4)

    readonly property real travel: Math.max(0, (root.width - width) * root.reach)

    readonly property real journey: {
      if (root.progress <= root.outboundEnd)
        return root.progress / root.outboundEnd
      if (root.progress >= root.inboundStart)
        return 1 - (root.progress - root.inboundStart) / (1 - root.inboundStart)
      return 1
    }

    // Starts and ends just off the left edge, so the hero arrives from
    // somewhere and goes back to it.
    x: Math.round(-width + (width + travel) * journey)

    // Turned around for the walk home, which is the only place mirroring is
    // used outside the arena.
    mirrored: root.progress > root.inboundStart

    bank: root.game ? root.game.sprites : null
    body: root.game && root.game.world && root.game.world.hero ? root.game.world.hero.race : ""
    overlay: root.game && root.game.world && root.game.world.hero ? root.game.world.hero.cls : ""
    anim: root.game ? root.game.strollAnim : "walk"
    tint: root.tint
    playing: root.visible

    // Fades at both ends, so the hero does not pop in and out at the edge.
    opacity: {
      if (root.progress < 0.05) return root.progress / 0.05
      if (root.progress > 0.95) return (1 - root.progress) / 0.05
      return 1
    }
  }
}
