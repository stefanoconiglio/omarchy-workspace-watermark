import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons

// Per-workspace watermark: a thin frame around each screen in the active
// workspace's hue, plus a faint project label in one corner. It sits on the
// overlay layer so it stays visible over fullscreen windows, and its input
// region is empty so it never takes clicks.
//
// Settings are read from this plugin's own entry in shell.json's plugins[].
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: manifest && manifest.id ? manifest.id : "io.github.stefanoconiglio.workspace-watermark"
  readonly property string shellConfigPath: Quickshell.env("HOME") + "/.config/omarchy/shell.json"

  property string shellConfigText: ""
  property var config: ({})

  // The shell rewrites shell.json for unrelated reasons (other plugins saving
  // their settings), so only adopt the file's `visible` when it changes;
  // otherwise a toggle that could not be persisted would snap back.
  property bool shown: true
  property var lastFileVisible: undefined

  readonly property string position: String(config.position || "bottom-right")
  readonly property real frameWidth: num(config.frameWidth, 3)
  readonly property real frameOpacity: num(config.frameOpacity, 0.6)
  readonly property real labelOpacity: num(config.labelOpacity, 0.14)
  readonly property bool flashOnSwitch: config.flashOnSwitch !== false
  readonly property bool autoDetectProject: config.autoDetectProject !== false
  readonly property var labels: config.labels || ({})
  readonly property var colors: config.colors || ({})

  // Window titles are "<file> - <project> - <editor>"; the project is the
  // segment right before the editor suffix.
  readonly property var editorSuffixes: [" - Visual Studio Code", " - VSCodium", " - Cursor", " - Code - OSS"]

  function num(value, fallback) {
    if (value === null || value === undefined || value === "") return fallback
    var n = Number(value)
    return isFinite(n) ? n : fallback
  }

  // A file caught mid-write fails to parse; keep the previous settings until
  // the next change notification brings the finished file.
  function applyShellConfig() {
    var parsed
    try {
      parsed = JSON.parse(shellConfigText || "{}")
    } catch (e) {
      return
    }
    var plugins = parsed && Array.isArray(parsed.plugins) ? parsed.plugins : []
    var entry = ({})
    for (var i = 0; i < plugins.length; i++) {
      if (plugins[i] && plugins[i].id === pluginId) entry = plugins[i]
    }
    config = entry
  }

  onShellConfigTextChanged: applyShellConfig()
  onPluginIdChanged: applyShellConfig()

  onConfigChanged: {
    var fileVisible = config.visible !== false
    if (fileVisible === lastFileVisible) return
    lastFileVisible = fileVisible
    shown = fileVisible
  }

  // Persist through the shell so the choice survives restarts. The shell
  // replaces the whole entry, so pass every current setting along.
  function setShown(value) {
    shown = value
    var entry = {}
    for (var key in config) if (key !== "id") entry[key] = config[key]
    entry.visible = value
    if (shell && shell.updateEntryInline(pluginId, entry)) lastFileVisible = value
  }

  function numberFor(ws) {
    if (!ws) return ""
    return ws.id === 10 ? "0" : String(ws.id)
  }

  function hueFor(ws) {
    if (!ws) return "transparent"
    var custom = root.colors[String(ws.id)] || root.colors[ws.name]
    if (custom) return custom
    // Golden-ratio steps keep neighbouring workspaces far apart on the wheel.
    var index = ws.id > 0 ? ws.id - 1 : 0
    return Qt.hsla((0.58 + index * 0.381966) % 1, 0.7, 0.62, 1)
  }

  function editorProject(title) {
    title = String(title || "")
    for (var i = 0; i < editorSuffixes.length; i++) {
      var suffix = editorSuffixes[i]
      if (title.length <= suffix.length || title.slice(-suffix.length) !== suffix) continue
      var parts = title.slice(0, -suffix.length).split(" - ")
      var project = parts[parts.length - 1].replace(/\s*\[[^\]]*\]\s*$/, "").trim()
      return project.replace(/[-_]{2,}/g, " ")
    }
    return ""
  }

  function detectProject(ws) {
    var windows = ws.toplevels ? ws.toplevels.values : []
    var counts = {}
    var best = ""
    var bestCount = 0
    for (var i = 0; i < windows.length; i++) {
      var project = editorProject(windows[i].title)
      if (!project) continue
      counts[project] = (counts[project] || 0) + 1
      if (counts[project] > bestCount) {
        best = project
        bestCount = counts[project]
      }
    }
    return best
  }

  function labelFor(ws) {
    if (!ws) return ""
    var explicit = root.labels[String(ws.id)] || root.labels[ws.name]
    if (explicit) return String(explicit)
    if (ws.name && ws.name !== String(ws.id)) return ws.name
    return root.autoDetectProject ? detectProject(ws) : ""
  }

  FileView {
    path: root.shellConfigPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.shellConfigText = text()
  }

  IpcHandler {
    target: "workspace-watermark"

    function toggle(): string {
      root.setShown(!root.shown)
      return root.shown ? "on" : "off"
    }

    function show(): string {
      root.setShown(true)
      return "on"
    }

    function hide(): string {
      root.setShown(false)
      return "off"
    }

    function state(): string {
      return root.shown ? "on" : "off"
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      readonly property var monitor: Hyprland.monitorFor(modelData)
      readonly property var workspace: monitor ? monitor.activeWorkspace : null
      readonly property color hue: root.hueFor(workspace)
      readonly property string number: root.numberFor(workspace)
      readonly property string project: root.labelFor(workspace)
      readonly property bool atTop: root.position.indexOf("top") === 0
      readonly property bool atLeft: root.position.indexOf("left") !== -1

      // 1 right after a workspace switch, easing back to 0.
      property real flash: 0

      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "workspace-watermark"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}

      onWorkspaceChanged: if (root.flashOnSwitch && workspace) flashAnimation.restart()

      NumberAnimation {
        id: flashAnimation
        target: panel
        property: "flash"
        from: 1
        to: 0
        duration: 1400
        easing.type: Easing.InQuad
      }

      // Stay mapped and fade the content instead: remapping would restack the
      // layer above notifications and menus that were mapped before it.
      Item {
        anchors.fill: parent
        opacity: root.shown && panel.workspace ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Rectangle {
          anchors.fill: parent
          color: "transparent"
          border.width: root.frameWidth
          border.color: Qt.rgba(panel.hue.r, panel.hue.g, panel.hue.b, root.frameOpacity)
          Behavior on border.color { ColorAnimation { duration: 250 } }
        }

        Column {
          id: label
          spacing: 2
          opacity: root.labelOpacity + (0.85 - root.labelOpacity) * panel.flash

          // Clear the bar at the top and editor status bars at the bottom.
          anchors.top: panel.atTop ? parent.top : undefined
          anchors.bottom: panel.atTop ? undefined : parent.bottom
          anchors.left: panel.atLeft ? parent.left : undefined
          anchors.right: panel.atLeft ? undefined : parent.right
          anchors.topMargin: 56
          anchors.bottomMargin: 48
          anchors.leftMargin: 36
          anchors.rightMargin: 36

          Text {
            anchors.left: panel.atLeft ? parent.left : undefined
            anchors.right: panel.atLeft ? undefined : parent.right
            text: panel.project || panel.number
            color: panel.hue
            font.family: Style.font.family
            font.pixelSize: panel.project ? 46 : 110
            font.weight: Font.Bold
          }

          Text {
            anchors.left: panel.atLeft ? parent.left : undefined
            anchors.right: panel.atLeft ? undefined : parent.right
            visible: panel.project !== ""
            text: "workspace " + panel.number
            color: panel.hue
            font.family: Style.font.family
            font.pixelSize: 18
            font.weight: Font.DemiBold
          }
        }
      }
    }
  }
}
