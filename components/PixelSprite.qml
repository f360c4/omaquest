pragma ComponentBehavior: Bound

import QtQuick

// Draws a 1-bit sprite: a body grid, optionally a class overlay on top, in one
// tint. Nearest-neighbour by construction — every run of lit cells is a
// rectangle on integer pixels — so it stays sharp at 16, 48 and 64 across.
//
// Six animations out of two frames. Only `idle_a` and `idle_b` exist per body;
// walking, fighting, being hurt, sleeping and cheering are the same two frames
// with a different cadence, a one-pixel offset, or a generic effect grid laid
// over them. That is what keeps the sheet at nineteen files instead of ninety.
//
// Drawn as scene-graph rectangles rather than on a Canvas. A Canvas would
// rasterise an image and re-upload a texture on every frame change — for ever,
// for one sixteen-pixel icon that breathes. Here both frames of every layer
// are built once as batched geometry and a frame change is two `visible`
// flips.
//
// Named PixelSprite, not Sprite: `QtQuick` already exports a `Sprite`, for the
// AnimatedSprite/SpriteSequence engine, and it wins the name over a file in
// the same directory. It is not an Item, so the collision surfaces as "Cannot
// assign to non-existent property anchors" from whichever file placed one.
Item {
  id: root

  property var bank: null

  property string body: ""        // a race: human, dwarf, elf, orc, automaton
  property string overlay: ""     // a class: warrior, rogue, bard, druid, mage
  // idle | wounded | walk | fight | hurt | sleep | cheer.
  //
  // `hurt` is a flinch: a short blink, driven by the service's transient
  // animation timer, and over in well under a second. `wounded` is the state
  // of being low on health, and it does not blink at all — it is a slower
  // breath and a body that sits a pixel lower. A sprite that blinks for as
  // long as health is low blinks for half an hour, and nobody wants a bar
  // widget flashing at them while they work.
  property string anim: "idle"
  property color tint: "white"
  property bool mirrored: false

  // Off when the sprite is not on screen. The bar widget is always mounted, so
  // without this a hidden panel would animate forever for nobody.
  property bool playing: visible

  readonly property int cells: bank ? bank.size : 16
  readonly property real cell: cells > 0 ? width / cells : 0

  // Bound through the bank's revision so layers fill in as the grids arrive
  // rather than staying empty until something else changes.
  readonly property int bankRevision: bank ? bank.revision : 0

  // ---- Cadence. `hurt` is the odd one: it blinks rather than steps.
  readonly property int frameMs: {
    switch (anim) {
      case "walk": return 600
      case "fight": return 350
      case "sleep": return 1200
      case "cheer": return 250
      case "hurt": return 110
      case "flourish": return 220
      case "wounded": return 1500
      default: return 900
    }
  }

  property int frame: 0

  // Sleeping holds one pose and lets the effect do the moving; being hurt
  // holds one and blinks. Everything else alternates the body's two frames.
  readonly property bool bodyHolds: anim === "sleep" || anim === "hurt"
  readonly property string heldFrame: anim === "sleep" ? "b" : "a"

  // The generic effect laid over the body, if this animation has one.
  readonly property string effectSet: {
    if (anim === "sleep") return "fx_sleep"
    if (anim === "cheer" || anim === "flourish") return "fx_cheer"
    return ""
  }

  // ---- One-pixel offsets, which is the whole of the procedural animation.
  //      Walking rocks forward and back, being hurt flinches away, fighting
  //      pushes the weapon forward on the second frame.
  readonly property int bodyOffsetX: {
    if (anim === "walk") return frame === 0 ? -1 : 1
    if (anim === "hurt") return -1
    return 0
  }

  // Being wounded shows as posture rather than as motion: the whole body sits
  // one pixel lower, which at 16 across reads as slumped and costs nothing to
  // look at.
  readonly property int bodyOffsetY: anim === "wounded" ? 1 : 0

  // A flourish pushes whatever the class carries out in front of them — the
  // warrior's sword, the mage's staff, the archer's bow — which is the whole
  // reason it looks like six different things rather than one.
  readonly property int overlayOffsetX: {
    if ((anim === "fight" || anim === "flourish") && frame === 1) return mirrored ? -1 : 1
    return bodyOffsetX
  }

  // Being hurt is a blink, so half the frames show nothing at all.
  readonly property bool blanked: anim === "hurt" && frame === 1

  Timer {
    interval: root.frameMs
    running: root.playing && root.visible
    repeat: true
    onTriggered: root.frame = root.frame === 0 ? 1 : 0
  }

  // Leaving an animation must not leave the sprite mid-blink or mid-step.
  onAnimChanged: root.frame = 0

  // One frame of one layer: a Repeater over the grid's horizontal runs. Both
  // frames of a layer exist at once and take turns being visible, so a frame
  // change never creates or destroys an item.
  component Layer: Item {
    id: layer

    property var runs: []
    property int offsetX: 0
    property int offsetY: 0

    anchors.fill: parent

    Repeater {
      model: layer.runs

      Rectangle {
        required property var modelData

        // A mirrored run keeps its width and reflects its left edge.
        readonly property int column: root.mirrored
          ? root.cells - modelData.x - modelData.w
          : modelData.x

        x: Math.round((column + layer.offsetX) * root.cell)
        y: Math.round((modelData.y + layer.offsetY) * root.cell)
        // Rounded to whole device pixels and a whole cell wide, so
        // neighbouring runs meet without a seam at any scale.
        width: Math.ceil(modelData.w * root.cell)
        height: Math.ceil(root.cell)
        color: root.tint
        antialiasing: false
        // A one-pixel offset can push a run off the edge of the grid.
        visible: x >= 0 && x + width <= root.width && y + height <= root.height
      }
    }
  }

  Item {
    anchors.fill: parent
    visible: !root.blanked && root.cell > 0

    // ---- Body, both frames.
    Layer {
      visible: root.bodyHolds ? root.heldFrame === "a" : root.frame === 0
      offsetX: root.bodyOffsetX
      offsetY: root.bodyOffsetY
      runs: { root.bankRevision; return root.bank ? root.bank.runs(root.body, root.anim, "a") : [] }
    }

    Layer {
      visible: root.bodyHolds ? root.heldFrame === "b" : root.frame === 1
      offsetX: root.bodyOffsetX
      offsetY: root.bodyOffsetY
      runs: { root.bankRevision; return root.bank ? root.bank.runs(root.body, root.anim, "b") : [] }
    }

    // ---- Class overlay, both frames. Absent on an enemy, and on a race card
    //      that has not been given a class yet.
    Loader {
      anchors.fill: parent
      active: root.overlay !== ""

      sourceComponent: Item {
        anchors.fill: parent

        Layer {
          visible: root.frame === 0
          offsetX: root.overlayOffsetX
          offsetY: root.bodyOffsetY
          runs: { root.bankRevision; return root.bank ? root.bank.runs(root.overlay + "_gear", root.anim, "a") : [] }
        }

        Layer {
          visible: root.frame === 1
          offsetX: root.overlayOffsetX
          offsetY: root.bodyOffsetY
          runs: { root.bankRevision; return root.bank ? root.bank.runs(root.overlay + "_gear", root.anim, "b") : [] }
        }
      }
    }

    // ---- The effect, if this animation has one. Never mirrored and never
    //      offset: a "z" reads as sleep only one way round, and sparks do not
    //      walk with the hero.
    Loader {
      anchors.fill: parent
      active: root.effectSet !== ""

      sourceComponent: Item {
        anchors.fill: parent

        Layer {
          visible: root.frame === 0
          runs: { root.bankRevision; return root.bank ? root.bank.runs(root.effectSet, "idle", "a") : [] }
        }

        Layer {
          visible: root.frame === 1
          runs: { root.bankRevision; return root.bank ? root.bank.runs(root.effectSet, "idle", "b") : [] }
        }
      }
    }
  }
}
