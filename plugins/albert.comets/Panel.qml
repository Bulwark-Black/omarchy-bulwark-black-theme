import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar widget for the Bulwark Black wallpaper's travelling current.
//
// Writes ~/.config/omarchy/bulwark-comets.json; the background plugin
// (albert.background) watches that file and applies changes live, so the two
// plugins stay decoupled — no cross-plugin imports, and the wallpaper keeps
// working if this widget is removed.
Panel {
  id: root
  moduleName: "albert.comets"
  ipcTarget: "albert.comets"

  // The bar sizes each slot from this root's implicit size (Bar.qml:1581),
  // so forward the button's — without this the widget loads but paints nothing.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string settingsPath: Quickshell.env("HOME") + "/.config/omarchy/bulwark-comets.json"

  // Defaults: slower and thinner than the site, which is tuned for a busy page
  // rather than a desktop you look at all day.
  readonly property int defaultCount: 6
  readonly property real defaultSpeed: 0.55
  readonly property real defaultThickness: 0.6
  readonly property int defaultLogoSize: 880

  property int logoSize: defaultLogoSize
  // Written by set-logo.sh, not by this panel — but it has to be carried
  // through save() or a slider release silently discards it.
  property string logoPath: ""
  property int count: defaultCount
  property real speed: defaultSpeed
  property real thickness: defaultThickness
  property bool loaded: false

  function loadSettings(raw) {
    try {
      var d = raw ? JSON.parse(raw) : {}
      if (typeof d.count === "number") count = Math.max(0, Math.min(24, Math.round(d.count)))
      if (typeof d.speed === "number") speed = Math.max(0.15, Math.min(2.5, d.speed))
      if (typeof d.thickness === "number") thickness = Math.max(0.25, Math.min(2.5, d.thickness))
      if (typeof d.logoSize === "number") logoSize = Math.max(200, Math.min(2000, Math.round(d.logoSize)))
      if (typeof d.logoPath === "string") logoPath = d.logoPath
    } catch (e) {
      // Corrupt file: fall back to defaults rather than leaving the panel dead.
    }
    loaded = true
  }

  function save() {
    if (!loaded) return
    settingsFile.setText(JSON.stringify({
      version: 1,
      count: root.count,
      speed: Number(root.speed.toFixed(3)),
      thickness: Number(root.thickness.toFixed(3)),
      logoSize: root.logoSize,
      logoPath: root.logoPath
    }, null, 2) + "\n")
  }

  function resetDefaults() {
    count = defaultCount
    speed = defaultSpeed
    thickness = defaultThickness
    logoSize = defaultLogoSize
    logoPath = Quickshell.env("HOME")
      + "/.config/omarchy/themes/bulwark-black/tools/assets/logo.png"
    save()
    // Also puts the branded wallpaper and original emblem back.
    defaultsProc.running = true
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    // set-logo.sh writes this file too (logoPath, and --defaults rewrites the
    // lot). Without watching it, the panel showed stale values after a reset.
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadSettings(text())
    onFileChanged: reload()
    // First run: no file yet. Load defaults, then write them so the background
    // plugin has something to watch.
    onLoadFailed: { root.loadSettings(""); root.save() }
  }

  // Picks an image, validates it, rebuilds the wallpaper around it and applies
  // it. Output lands in ~/.config/omarchy/backgrounds/bulwark-black/ so the
  // shipped branded wallpaper is never overwritten.
  // setsid detaches it. A bar panel is loaded on demand, so closing the panel to
  // uncover the fullscreen picker was tearing down this Process before it ran.
  // Rebuilds with the logo already chosen — lets the Size field take effect
  // without re-picking the file. ~1.7s with the base layer cached.
  // Full restore: shipped Bulwark emblem, shipped wallpaper, default values.
  // The script owns it so the wallpaper and the settings file cannot drift apart.
  Process {
    id: defaultsProc
    command: ["bash", "-c",
      "setsid -f \"$HOME/.config/omarchy/themes/bulwark-black/tools/set-logo.sh\" --defaults >/dev/null 2>&1"]
  }

  Process {
    id: rebuildProc
    command: ["bash", "-c",
      "setsid -f \"$HOME/.config/omarchy/themes/bulwark-black/tools/set-logo.sh\" --rebuild >/dev/null 2>&1"]
  }

  Process {
    id: logoProc
    command: ["bash", "-c",
      "setsid -f \"$HOME/.config/omarchy/themes/bulwark-black/tools/set-logo.sh\" >/dev/null 2>&1"]
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    tooltipText: "Wallpaper comets"
    onPressed: function(b) {
      if (b === Qt.RightButton) root.resetDefaults()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        PanelSectionHeader {
          width: parent.width
          foreground: root.bar ? root.bar.foreground : Color.foreground
          text: "TRAVELLING CURRENT"
        }

        // ---- Speed ------------------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            implicitHeight: speedLabelField.height
            Text {
              id: speedLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Speed (%)"
              textFormat: Text.PlainText
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            NumberField {
              id: speedLabelField
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              from: 15
              to: 200
              stepSize: 5
              value: Math.round(root.speed * 100)
              foreground: root.bar ? root.bar.foreground : Color.foreground
              accent: Color.accent
              fontFamily: Style.font.family
              onModified: function(v) { root.speed = v / 100; root.save() }
            }
          }

          PanelSlider {
            bar: root.bar
            width: parent.width
            minimum: 0.15
            maximum: 2.0
            step: 0.05
            value: root.speed
            onMoved: function(v) { root.speed = v }
            onReleased: function(v) { root.speed = v; root.save() }
          }
        }

        // ---- Thickness --------------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            implicitHeight: thickLabelField.height
            Text {
              id: thickLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Thickness (%)"
              textFormat: Text.PlainText
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            NumberField {
              id: thickLabelField
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              from: 25
              to: 200
              stepSize: 5
              value: Math.round(root.thickness * 100)
              foreground: root.bar ? root.bar.foreground : Color.foreground
              accent: Color.accent
              fontFamily: Style.font.family
              onModified: function(v) { root.thickness = v / 100; root.save() }
            }
          }

          PanelSlider {
            bar: root.bar
            width: parent.width
            minimum: 0.25
            maximum: 2.0
            step: 0.05
            value: root.thickness
            onMoved: function(v) { root.thickness = v }
            onReleased: function(v) { root.thickness = v; root.save() }
          }
        }

        // ---- Count ------------------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            implicitHeight: countLabelField.height
            Text {
              id: countLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Comets"
              textFormat: Text.PlainText
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            NumberField {
              id: countLabelField
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              from: 0
              to: 20
              stepSize: 1
              value: root.count
              foreground: root.bar ? root.bar.foreground : Color.foreground
              accent: Color.accent
              fontFamily: Style.font.family
              onModified: function(v) { root.count = v; root.save() }
            }
          }

          PanelSlider {
            bar: root.bar
            width: parent.width
            minimum: 0
            maximum: 20
            step: 1
            integer: true
            value: root.count
            onMoved: function(v) { root.count = Math.round(v) }
            onReleased: function(v) { root.count = Math.round(v); root.save() }
          }
        }

        PanelSeparator { width: parent.width }

        PanelSectionHeader {
          width: parent.width
          foreground: root.bar ? root.bar.foreground : Color.foreground
          text: "LOGO"
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            implicitHeight: logoLabelField.height
            Text {
              id: logoLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Size (px)"
              textFormat: Text.PlainText
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            NumberField {
              id: logoLabelField
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              from: 200
              to: 1600
              stepSize: 20
              value: root.logoSize
              foreground: root.bar ? root.bar.foreground : Color.foreground
              accent: Color.accent
              fontFamily: Style.font.family
              onModified: function(v) { root.logoSize = v; root.save() }
            }
          }

          PanelSlider {
            bar: root.bar
            width: parent.width
            minimum: 200
            maximum: 1600
            step: 20
            integer: true
            value: root.logoSize
            onMoved: function(v) { root.logoSize = Math.round(v) }
            onReleased: function(v) { root.logoSize = Math.round(v); root.save() }
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(chooseLabel.implicitHeight, chooseBtn.height)

            Text {
              id: chooseLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Choose · rebuild"
              textFormat: Text.PlainText
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            PanelActionButton {
              id: rebuildBtn
              anchors.right: chooseBtn.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰑐"
              tooltipText: "Rebuild the wallpaper at this size"
              foreground: root.bar ? root.bar.foreground : Color.foreground
              fontFamily: Style.font.family
              onClicked: {
                rebuildProc.running = true
                Qt.callLater(function() { root.close() })
              }
            }

            PanelActionButton {
              id: chooseBtn
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰋩"
              tooltipText: "Pick a logo and rebuild the wallpaper"
              foreground: root.bar ? root.bar.foreground : Color.foreground
              fontFamily: Style.font.family
              onClicked: {
                // Launch first, close second: the other order raced the panel
                // teardown and the script never started.
                logoProc.running = true
                Qt.callLater(function() { root.close() })
              }
            }
          }
        }

        PanelSeparator { width: parent.width }

        Item {
          width: parent.width
          implicitHeight: Math.max(resetLabel.implicitHeight, resetBtn.height)
          Text {
            id: resetLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Reset to defaults"
            textFormat: Text.PlainText
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          PanelActionButton {
            id: resetBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰜉"
            tooltipText: "Bulwark emblem, shipped wallpaper, default values"
            foreground: root.bar ? root.bar.foreground : Color.foreground
            fontFamily: Style.font.family
            onClicked: {
              root.resetDefaults()
              Qt.callLater(function() { root.close() })
            }
          }
        }

        Text {
          width: parent.width
          text: "PNG with transparency, light artwork, 512px+."
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.6)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
