import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import qs.Ui

Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"

  property string currentBackground: ""
  property string displayedBackground: ""
  property string incomingBackground: ""
  property string oldBackground: ""
  property bool finishingTransition: false
  property int backgroundVersion: 0
  property int revealStartedVersion: -1
  property int pendingThemeVersion: -1
  property string pendingColorsRaw: ""
  property string pendingShellRaw: ""
  property real revealProgress: 1

  function imageUrl(path) {
    return Util.fileUrl(path)
  }

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function setBackground(path, instant) {
    transitionBackground("", path, path, instant, false)
  }

  function transitionBackground(fromPath, path, finalPath, instant, force) {
    path = String(path || "").trim()
    finalPath = String(finalPath || path).trim()
    fromPath = String(fromPath || "").trim()
    if (!path || (!force && finalPath === currentBackground)) return
    currentBackground = finalPath
    backgroundVersion += 1
    revealStartedVersion = -1

    revealAnimation.stop()
    finishingTransition = false

    if (instant || !displayedBackground) {
      oldBackground = ""
      incomingBackground = ""
      displayedBackground = path
      revealProgress = 1
      return
    }

    oldBackground = fromPath || displayedBackground
    incomingBackground = path
    revealProgress = 0
  }

  function setPendingTheme(colorsB64, shellB64) {
    pendingColorsRaw = Util.decodeBase64(colorsB64)
    pendingShellRaw = Util.decodeBase64(shellB64)
    pendingThemeVersion = backgroundVersion
    pendingThemeFallbackTimer.restart()
  }

  function applyPendingTheme() {
    // Background polling can advance backgroundVersion while a theme switch is
    // pending; the latest theme payload should still apply.
    if (pendingThemeVersion < 0) return
    pendingThemeFallbackTimer.stop()
    Color.loadColors(pendingColorsRaw)
    // Color.loadShell also refreshes Style so the type scale flips with the
    // background reveal instead of waiting for a separate reload path.
    Color.loadShell(pendingShellRaw)
    Style.scheduleRefresh()
    pendingThemeVersion = -1
    pendingColorsRaw = ""
    pendingShellRaw = ""
  }

  function transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64) {
    transitionBackground(fromPath, path, finalPath, false, true)
    setPendingTheme(colorsB64, shellB64)
    if (!incomingBackground || revealProgress >= 1) applyPendingTheme()
  }

  function startReveal(panel) {
    if (!incomingBackground) return
    panel.maskReady = true
    if (revealStartedVersion === backgroundVersion) return
    revealStartedVersion = backgroundVersion
    applyPendingTheme()
    revealAnimation.restart()
  }

  function openSelector() {
    if (!bgSwitchProc.running) bgSwitchProc.running = true
  }

  function openThemeSwitcher() {
    if (!themeSwitchProc.running) themeSwitchProc.running = true
  }

  Process {
    id: bgSwitchProc
    command: ["bash", "-c", "background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set \"$background\""]
    onExited: root.refreshBackground()
  }

  Process {
    id: themeSwitchProc
    command: ["bash", "-c", "theme=$(omarchy-theme-switcher); [[ -n $theme ]] && omarchy-theme-set \"$theme\" >/dev/null 2>&1 &"]
    onExited: root.refreshBackground()
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      onStreamFinished: root.setBackground(String(text || "").trim(), false)
    }
  }

  IpcHandler {
    target: "background"

    function refresh(): void {
      root.refreshBackground()
    }

    function set(path: string): void {
      root.setBackground(path, false)
    }

    function setInstant(path: string): void {
      root.setBackground(path, true)
    }

    function transition(fromPath: string, path: string): void {
      root.transitionBackground(fromPath, path, path, false, false)
    }

    function themeTransition(fromPath: string, path: string, finalPath: string, colorsB64: string, shellB64: string): void {
      root.transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64)
    }
  }

  Timer {
    id: pendingThemeFallbackTimer
    interval: 300
    repeat: false
    onTriggered: root.applyPendingTheme()
  }

  NumberAnimation {
    id: revealAnimation
    target: root
    property: "revealProgress"
    from: 0
    to: 1
    duration: 420
    easing.type: Easing.InOutCubic
    onFinished: {
      if (root.incomingBackground) {
        root.displayedBackground = root.currentBackground || root.incomingBackground
        root.finishingTransition = true
      }
      root.revealProgress = 1
    }
  }

  Component.onCompleted: refreshBackground()

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      visible: !remapGuard.remapping
      anchors { top: true; bottom: true; left: true; right: true }

      ScreenMoveRemap {
        id: remapGuard
        window: panel
      }
      color: "transparent"
      // Keep render updates enabled. The background layer has been observed to
      // lose its committed buffer while parked with updatesEnabled=false,
      // leaving a black desktop until omarchy-shell is restarted. The wallpaper
      // itself is static, so this favors correctness over a small render-loop
      // optimization.
      updatesEnabled: true

      property bool maskReady: false

      function maybeStartReveal() {
        if (!root.incomingBackground || root.revealProgress !== 0 || maskReady) return
        if (incomingFrame.status !== Image.Ready) return
        Qt.callLater(function() {
          if (!root.incomingBackground || root.revealProgress !== 0 || maskReady) return
          if (incomingFrame.status !== Image.Ready) return
          root.startReveal(panel)
        })
      }

      WlrLayershell.namespace: "omarchy-background"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      Image {
        id: base
        anchors.fill: parent
        source: root.imageUrl(root.displayedBackground)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        onStatusChanged: {
          if (status === Image.Ready && root.finishingTransition) {
            root.incomingBackground = ""
            root.oldBackground = ""
            root.finishingTransition = false
          }
        }
      }


      // --- Bulwark Black: travelling current -------------------------------
      // Ported from the site's CircuitBackground.astro: same 12 trace paths,
      // same SCALE 0.7 (224px tile) so comets land on the wires baked into the
      // wallpaper image, same 4-layer comet, same random reroute each cycle,
      // same fade envelope.
      //
      // Speed / thickness / count come from ~/.config/omarchy/bulwark-comets.json,
      // written by the albert.comets bar widget and watched here, so the two
      // plugins stay decoupled. Defaults apply if that file is absent.
      //
      // Only runs on the circuit wallpaper; every other background stays static.
      Item {
        id: currentLayer
        anchors.fill: parent
        visible: root.displayedBackground.indexOf("circuit") >= 0
        z: base.z + 1

        property int cometCount: 6
        property real speedScale: 0.55
        property real widthScale: 0.6

        function applySettings(raw) {
          try {
            var d = raw ? JSON.parse(raw) : {}
            if (typeof d.count === "number") cometCount = Math.max(0, Math.min(24, Math.round(d.count)))
            if (typeof d.speed === "number") speedScale = Math.max(0.15, Math.min(2.5, d.speed))
            if (typeof d.thickness === "number") widthScale = Math.max(0.25, Math.min(2.5, d.thickness))
          } catch (e) {
            // Corrupt or half-written file: keep whatever we already had.
          }
        }

        FileView {
          path: Quickshell.env("HOME") + "/.config/omarchy/bulwark-comets.json"
          watchChanges: true
          printErrors: false
          onLoaded: currentLayer.applySettings(text())
          // watchChanges only emits the signal; the reload is ours to make.
          onFileChanged: reload()
        }

        readonly property int step: 224
        readonly property var traces: [
          { d: "M0,60 L80,60 L80,90 L160,90 L160,60 L240,60 L240,30 L320,30", len: 287.00 },
          { d: "M0,180 L40,180 L40,150 L130,150 L130,180 L210,180 L210,210 L320,210", len: 287.00 },
          { d: "M0,260 L90,260 L90,290 L200,290 L200,260 L320,260", len: 266.00 },
          { d: "M30,0 L30,40 L70,40 L70,80", len: 84.00 },
          { d: "M120,0 L120,30 L100,30 L100,60", len: 56.00 },
          { d: "M200,0 L200,20 L180,20 L180,50", len: 49.00 },
          { d: "M280,0 L280,60 L260,60 L260,90 L290,90 L290,120", len: 119.00 },
          { d: "M50,320 L50,290 L75,290 L75,250", len: 66.50 },
          { d: "M150,320 L150,300 L130,300 L130,240", len: 70.00 },
          { d: "M240,320 L240,270 L260,270 L260,220", len: 84.00 },
          { d: "M160,90 L160,120 L190,120 L190,160", len: 70.00 },
          { d: "M230,150 L230,110 L260,110 L260,140", len: 70.00 }
        ]

        Repeater {
          model: currentLayer.cometCount
          delegate: Item {
            id: comet
            anchors.fill: parent

            property string d: ""
            property real len: 1
            property real travel: 0
            property real durBase: 2800 + Math.random() * 3700   // site: rand(2.8, 6.5)s
            property real dur: durBase / Math.max(0.05, currentLayer.speedScale)

            function reroute() {
              var t = currentLayer.traces[Math.floor(Math.random() * currentLayer.traces.length)]
              var cols = Math.max(1, Math.ceil(width / currentLayer.step))
              var rows = Math.max(1, Math.ceil(height / currentLayer.step))
              var ox = Math.floor(Math.random() * cols) * 320
              var oy = Math.floor(Math.random() * rows) * 320
              comet.d = t.d.replace(/(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/g, function (_m, x, y) {
                return ((parseFloat(x) + ox) * 0.7).toFixed(2) + "," + ((parseFloat(y) + oy) * 0.7).toFixed(2)
              })
              comet.len = t.len
            }

            Component.onCompleted: { reroute(); run.start() }

            SequentialAnimation {
              id: run
              loops: Animation.Infinite
              NumberAnimation {
                target: comet; property: "travel"
                from: 0; to: comet.len
                duration: comet.dur
                easing.type: Easing.Linear
              }
              // New duration and a new wire are picked up here, so a slider move
              // lands within one cycle instead of needing a restart.
              ScriptAction { script: comet.reroute() }
            }

            // Site's epulse-fade: in fast, hold, dip, flicker, out.
            readonly property real phase: comet.travel / Math.max(comet.len, 1)
            opacity: 0.7 * (phase < 0.07 ? phase / 0.07
                          : phase < 0.68 ? 1.0
                          : phase < 0.82 ? 1.0 - (phase - 0.68) / 0.14 * 0.65
                          : phase < 0.88 ? 0.35 + (phase - 0.82) / 0.06 * 0.35
                          : 1.0 - (phase - 0.88) / 0.12)

            Shape {
              anchors.fill: parent
              antialiasing: true
              preferredRendererType: Shape.GeometryRenderer
              ShapePath {
                strokeColor: "#a8842f"
                strokeWidth: (7.0 * currentLayer.widthScale)
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                strokeStyle: ShapePath.DashLine
                // dashPattern is in strokeWidth units, unlike SVG's user units,
                // so the absolute lit length has to be divided by the live width.
                dashPattern: [ comet.len * 0.26 / (7.0 * currentLayer.widthScale), comet.len * 0.74 / (7.0 * currentLayer.widthScale) ]
                dashOffset: (comet.len * 0.26 - comet.travel) / (7.0 * currentLayer.widthScale)
                PathSvg { path: comet.d }
              }
              ShapePath {
                strokeColor: "#e0b64d"
                strokeWidth: (3.5 * currentLayer.widthScale)
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                strokeStyle: ShapePath.DashLine
                // dashPattern is in strokeWidth units, unlike SVG's user units,
                // so the absolute lit length has to be divided by the live width.
                dashPattern: [ comet.len * 0.18 / (3.5 * currentLayer.widthScale), comet.len * 0.82 / (3.5 * currentLayer.widthScale) ]
                dashOffset: (comet.len * 0.18 - comet.travel) / (3.5 * currentLayer.widthScale)
                PathSvg { path: comet.d }
              }
              ShapePath {
                strokeColor: "#f2c14e"
                strokeWidth: (1.8 * currentLayer.widthScale)
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                strokeStyle: ShapePath.DashLine
                // dashPattern is in strokeWidth units, unlike SVG's user units,
                // so the absolute lit length has to be divided by the live width.
                dashPattern: [ comet.len * 0.08 / (1.8 * currentLayer.widthScale), comet.len * 0.92 / (1.8 * currentLayer.widthScale) ]
                dashOffset: (comet.len * 0.08 - comet.travel) / (1.8 * currentLayer.widthScale)
                PathSvg { path: comet.d }
              }
              ShapePath {
                strokeColor: "#fff7e6"
                strokeWidth: (1.4 * currentLayer.widthScale)
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                strokeStyle: ShapePath.DashLine
                // dashPattern is in strokeWidth units, unlike SVG's user units,
                // so the absolute lit length has to be divided by the live width.
                dashPattern: [ comet.len * 0.04 / (1.4 * currentLayer.widthScale), comet.len * 0.96 / (1.4 * currentLayer.widthScale) ]
                dashOffset: (comet.len * 0.04 - comet.travel) / (1.4 * currentLayer.widthScale)
                PathSvg { path: comet.d }
              }
            }
          }
        }
      }
      // --- end travelling current -----------------------------------------

      Image {
        id: oldFrame
        anchors.fill: parent
        source: root.imageUrl(root.oldBackground)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
        visible: root.oldBackground !== "" && root.revealProgress < 1
        onStatusChanged: panel.maybeStartReveal()
      }

      Item {
        id: incomingLayer
        anchors.fill: parent
        visible: root.incomingBackground !== "" && incomingFrame.status === Image.Ready && (root.revealProgress >= 1 || panel.maskReady)
        layer.enabled: root.incomingBackground !== "" && root.revealProgress < 1
        layer.smooth: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: revealMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 0.02
        }

        Image {
          id: incomingFrame
          anchors.fill: parent
          source: root.imageUrl(root.incomingBackground)
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: false
          smooth: true
          mipmap: true
          onStatusChanged: panel.maybeStartReveal()
        }
      }

      Item {
        id: revealMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        readonly property real slant: -0.18
        readonly property real centerTop: width / 2 - slant * height / 2
        readonly property real centerBottom: width / 2 + slant * height / 2
        readonly property real reach: width / 2 + Math.abs(slant) * height / 2 + 4
        readonly property real spread: reach * root.revealProgress

        Shape {
          anchors.fill: parent
          antialiasing: true
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            fillColor: "white"
            strokeColor: "transparent"
            startX: revealMask.centerTop - revealMask.spread; startY: 0
            PathLine { x: revealMask.centerTop + revealMask.spread; y: 0 }
            PathLine { x: revealMask.centerBottom + revealMask.spread; y: revealMask.height }
            PathLine { x: revealMask.centerBottom - revealMask.spread; y: revealMask.height }
            PathLine { x: revealMask.centerTop - revealMask.spread; y: 0 }
          }
        }
      }

      Connections {
        target: root
        function onIncomingBackgroundChanged() {
          panel.maskReady = false
          panel.maybeStartReveal()
        }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onDoubleClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.openThemeSwitcher()
          else root.openSelector()
          mouse.accepted = true
        }
      }
    }
  }
}
