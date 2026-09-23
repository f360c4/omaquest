pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// The hero, out for a walk across the bottom of the screen.
//
// This is the only thing the plugin ever draws outside its own panel, and it
// only exists because somebody clicked. It walks one way, finds something, and
// is gone — forty seconds, no more than three times a day.
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

  readonly property int spriteSize: Style.space(48)

  // The largest connected output. A hero that strolls across the monitor
  // nobody is looking at has not strolled.
  screen: {
    var screens = Quickshell.screens
    var best = null
    for (var i = 0; i < screens.length; i++)
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
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore

  // Nothing here is clickable, and an empty input region is what guarantees
  // the hero can never eat a click meant for the desktop underneath.
  mask: Region {}

  PixelSprite {
    id: hero

    width: root.spriteSize
    height: root.spriteSize
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(4)

    // Walks in from off the left edge and leaves past the right, so it enters
    // and exits rather than appearing and vanishing.
    x: Math.round((root.width + width * 2) * root.progress) - width

    bank: root.game ? root.game.sprites : null
    body: root.game && root.game.world && root.game.world.hero ? root.game.world.hero.race : ""
    overlay: root.game && root.game.world && root.game.world.hero ? root.game.world.hero.cls : ""
    anim: "walk"
    tint: root.tint
    playing: root.visible

    // Fades at both ends, so the hero does not pop in at the screen edge.
    opacity: {
      if (root.progress < 0.06) return root.progress / 0.06
      if (root.progress > 0.94) return (1 - root.progress) / 0.06
      return 1
    }
  }
}
