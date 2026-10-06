import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons

// Per-workspace watermark: on each workspace switch, the workspace's name and
// the list of its windows (oldest process first) show in big letters in one
// corner, in the workspace's hue, then fade away (or, if set, to a faint
// watermark). The screen behind can be dimmed (`backdropOpacity`, off by
// default). An
// optional thin frame in the same hue goes around each screen. It sits on the
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
  readonly property bool frame: config.frame === true
  readonly property real frameWidth: num(config.frameWidth, 3)
  readonly property real frameOpacity: num(config.frameOpacity, 0.6)
  readonly property real labelOpacity: num(config.labelOpacity, 0.14)
  readonly property bool flashOnSwitch: config.flashOnSwitch !== false
  readonly property real flashDuration: Math.max(0, num(config.flashDuration, 2500))
  readonly property bool fadeAway: config.fadeAway !== false
  readonly property bool windowList: config.windowList !== false
  readonly property real fontSize: Math.max(12, num(config.fontSize, 60))
  readonly property real backdropOpacity: Math.min(1, Math.max(0, num(config.backdropOpacity, 0)))
  readonly property bool autoDetectProject: config.autoDetectProject !== false
  readonly property var labels: config.labels || ({})
  readonly property var colors: config.colors || ({})

  // Window titles are "<file> - <project> - <editor>"; the project is the
  // segment right before the editor suffix.
  readonly property var editorSuffixes: [" - Visual Studio Code", " - VSCodium", " - Cursor", " - Code - OSS"]

  // Terminals that run one process per window, so a window maps to one shell.
  readonly property var terminalClasses: ["foot", "Alacritty", "kitty", "com.mitchellh.ghostty", "org.wezfurlong.wezterm", "xterm"]

  // Chromium app windows are classed "<browser>-<host>_<path>-<profile>".
  readonly property var webAppClass: /^(?:brave|chrome|chromium|google-chrome|msedge|vivaldi)-([^_]+)_(.*)-[^-]+$/
  readonly property var webApps: webAppIndex(DesktopEntries.applications.values)

  readonly property string scanScript: decodeURIComponent(Qt.resolvedUrl("terminal-cwds.sh").toString().replace(/^file:\/\//, ""))

  // Asks every screen to show its overlay again (the `flash` command).
  signal flashRequested()

  // Terminal PID -> { shell: cwd, claude: cwd, program: name }, refreshed
  // every few seconds.
  property var terminalFolders: ({})
  property string terminalFoldersJson: "{}"

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
      return tidy(parts[parts.length - 1].replace(/\s*\[[^\]]*\]\s*$/, "").trim())
    }
    return ""
  }

  function tidy(name) {
    return String(name || "").replace(/[-_]{2,}/g, " ")
  }

  function folderName(path) {
    path = String(path || "").replace(/\/+$/, "")
    if (!path) return ""
    if (path === Quickshell.env("HOME")) return "~"
    return tidy(path.slice(path.lastIndexOf("/") + 1))
  }

  function appIdOf(window) {
    return window && window.wayland ? String(window.wayland.appId || "") : ""
  }

  function pidOf(window) {
    var ipc = window ? window.lastIpcObject : null
    return ipc && ipc.pid ? String(ipc.pid) : ""
  }

  function isTerminal(appId) {
    return terminalClasses.indexOf(appId) !== -1
  }

  // Web app launchers (omarchy-launch-webapp <url>) keyed the way Chromium
  // names app windows: host plus the URL path with slashes turned into "_".
  function webAppIndex(entries) {
    var exact = {}
    var byHost = {}
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      var args = entry && entry.command ? entry.command : []
      for (var j = 0; j < args.length; j++) {
        var m = String(args[j]).match(/^https?:\/\/([^\/?#]+)([^?#]*)/)
        if (!m) continue
        var host = m[1].toLowerCase()
        var path = m[2] || "/"
        exact[host + "_" + path.replace(/\//g, "_")] = entry.name
        if (!byHost[host] || path.length < byHost[host].pathLength)
          byHost[host] = { name: entry.name, pathLength: path.length }
        break
      }
    }
    return { exact: exact, byHost: byHost }
  }

  function webAppName(appId) {
    var m = appId.match(webAppClass)
    if (!m) return ""
    var host = m[1].toLowerCase()
    var named = webApps.exact[host + "_" + m[2]] || (webApps.byHost[host] || {}).name
    if (named) return named
    var parts = host.split(".")
    var core = parts.length > 1 ? parts[parts.length - 2] : parts[0]
    return core.charAt(0).toUpperCase() + core.slice(1)
  }

  // The best name one window offers, as [tier, name]; lower tiers win.
  function windowLabel(window) {
    var project = editorProject(window.title)
    if (project) return [0, project]
    var appId = appIdOf(window)
    if (isTerminal(appId)) {
      var folders = terminalFolders[pidOf(window)]
      if (folders && folders.claude) return [1, folderName(folders.claude)]
      if (folders && folders.shell) return [2, folderName(folders.shell)]
      return null
    }
    var web = webAppName(appId)
    if (web) return [3, web]
    var entry = appId ? DesktopEntries.heuristicLookup(appId) : null
    return entry && entry.name ? [4, entry.name] : null
  }

  // Take the best tier present on the workspace, then its most common name.
  function autoLabel(ws) {
    var windows = ws.toplevels ? ws.toplevels.values : []
    var bestTier = Infinity
    var counts = {}
    var best = ""
    var bestCount = 0
    for (var i = 0; i < windows.length; i++) {
      var found = windowLabel(windows[i])
      if (!found || found[0] > bestTier) continue
      if (found[0] < bestTier) {
        bestTier = found[0]
        counts = {}
        best = ""
        bestCount = 0
      }
      counts[found[1]] = (counts[found[1]] || 0) + 1
      if (counts[found[1]] > bestCount) {
        best = found[1]
        bestCount = counts[found[1]]
      }
    }
    return best
  }

  function labelFor(ws) {
    if (!ws) return ""
    var explicit = root.labels[String(ws.id)] || root.labels[ws.name]
    if (explicit) return String(explicit)
    if (ws.name && ws.name !== String(ws.id)) return ws.name
    return root.autoDetectProject ? autoLabel(ws) : ""
  }

  // The app a window belongs to: the program a terminal runs, a web app's
  // name, or the app's own name.
  function appName(window) {
    var appId = appIdOf(window)
    if (isTerminal(appId)) {
      var folders = terminalFolders[pidOf(window)]
      return folders && folders.program ? folders.program : "terminal"
    }
    var web = webAppName(appId)
    if (web) return web
    var entry = appId ? DesktopEntries.heuristicLookup(appId) : null
    return entry && entry.name ? entry.name : (appId || "window")
  }

  // What the window shows, from its title without the app's own suffix
  // (" - Brave", " - GNU Emacs at host"); "" when it only repeats the app.
  function windowDetail(window, app) {
    var title = String(window.title || "")
    var project = editorProject(title)
    if (project) return project
    var appId = appIdOf(window)
    if (isTerminal(appId)) {
      var folders = terminalFolders[pidOf(window)]
      if (folders && folders.program === "claude" && folders.claude) return folderName(folders.claude)
      // Shells title the window "user@host:dir"; herdr titles it "host: workspace".
      var rest = title.replace(/^([^@\s]+@)?[^:\s]+:\s*/, "")
      return rest || (folders ? folderName(folders.shell) : "")
    }
    var key = function(s) { return String(s).toLowerCase().replace(/[^a-z0-9]/g, "") }
    var marks = [key(app.split(" ")[0]), key(appId.split(/[-._]/)[0])]
    var parts = title.split(" - ")
    if (parts.length > 1) {
      var last = key(parts[parts.length - 1])
      for (var i = 0; i < marks.length; i++) {
        if (marks[i] && last.indexOf(marks[i]) !== -1) {
          parts.pop()
          break
        }
      }
    }
    var detail = parts.join(" - ").trim()
    // A bare host or the app's own name says nothing new.
    if (key(detail) === key(app) || (/^[\w.-]+$/.test(detail) && key(detail).indexOf(key(app)) !== -1)) return ""
    return detail
  }

  // The workspace's windows, oldest process first; windows of one process
  // (every Brave window, say) keep the order Hyprland lists them in.
  function windowRows(ws) {
    var windows = ws && ws.toplevels ? ws.toplevels.values : []
    var items = []
    for (var i = 0; i < windows.length; i++) {
      var pid = Number(pidOf(windows[i]))
      items.push({ window: windows[i], pid: pid > 0 ? pid : Infinity, index: i })
    }
    items.sort(function(a, b) { return a.pid !== b.pid ? (a.pid < b.pid ? -1 : 1) : a.index - b.index })
    var rows = []
    for (var j = 0; j < items.length; j++) {
      var app = appName(items[j].window)
      rows.push({ app: app, detail: windowDetail(items[j].window, app), pid: items[j].pid })
    }
    return rows
  }

  function scanTerminals() {
    if (terminalScan.running) return
    var pids = []
    var missingPid = false
    var windows = Hyprland.toplevels.values
    for (var i = 0; i < windows.length; i++) {
      var pid = pidOf(windows[i])
      // The list sorts every window by PID, not just terminals.
      if (!pid) missingPid = true
      if (!pid || !isTerminal(appIdOf(windows[i]))) continue
      if (pids.indexOf(pid) === -1) pids.push(pid)
    }
    // Window PIDs arrive with a toplevel refresh; new windows get one next tick.
    if (missingPid) Hyprland.refreshToplevels()
    if (pids.length === 0) {
      setTerminalFolders({})
      return
    }
    terminalScan.command = ["bash", scanScript].concat(pids)
    terminalScan.running = true
  }

  function setTerminalFolders(folders) {
    var json = JSON.stringify(folders)
    if (json === terminalFoldersJson) return
    terminalFoldersJson = json
    terminalFolders = folders
  }

  Timer {
    interval: 3000
    repeat: true
    triggeredOnStart: true
    running: root.shown && (root.autoDetectProject || root.windowList)
    onTriggered: root.scanTerminals()
  }

  Process {
    id: terminalScan
    stdout: StdioCollector {
      onStreamFinished: {
        var folders = {}
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var m = lines[i].match(/^(\d+) (shell|claude|program) (.+)$/)
          if (!m) continue
          var entry = folders[m[1]] || (folders[m[1]] = { shell: "", claude: "", program: "" })
          if (m[2] === "shell") entry.shell = m[3]
          else if (m[2] === "program") entry.program = m[3]
          else if (!entry.claude) entry.claude = m[3]
        }
        root.setTerminalFolders(folders)
      }
    }
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

    // Show the name and window list again, as after a switch.
    function flash(): string {
      root.flashRequested()
      return "flashed"
    }

    // Each workspace's window list as it would show, one
    // "<workspace> <pid> <app> — <detail>" line per window.
    function windows(): string {
      var workspaces = Hyprland.workspaces.values.slice()
      workspaces.sort(function(a, b) { return a.id - b.id })
      var lines = []
      for (var i = 0; i < workspaces.length; i++) {
        if (workspaces[i].id <= 0) continue
        var rows = root.windowRows(workspaces[i])
        for (var j = 0; j < rows.length; j++)
          lines.push(root.numberFor(workspaces[i]) + " " + rows[j].pid + " " + rows[j].app + (rows[j].detail ? " — " + rows[j].detail : ""))
      }
      return lines.join("\n")
    }

    // One "<workspace> <name>" line per workspace, for checking without switching.
    function names(): string {
      var workspaces = Hyprland.workspaces.values.slice()
      workspaces.sort(function(a, b) { return a.id - b.id })
      var lines = []
      for (var i = 0; i < workspaces.length; i++) {
        if (workspaces[i].id > 0) lines.push(root.numberFor(workspaces[i]) + " " + root.labelFor(workspaces[i]))
      }
      return lines.join("\n")
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
      readonly property var rows: root.windowList ? root.windowRows(workspace) : []
      readonly property bool atTop: root.position.indexOf("top") === 0
      readonly property bool atLeft: root.position.indexOf("left") !== -1

      // 1 right after a workspace switch, held, then easing back to 0.
      property real flash: 0
      // What stays between switches: nothing, or a faint watermark.
      readonly property real restOpacity: root.fadeAway ? 0 : root.labelOpacity

      // One big font for the name and every window: as large as fits the
      // screen's height, up to `fontSize`.
      readonly property real margin: 36
      readonly property real maxWidth: Math.max(0, width - 2 * margin)
      readonly property real textSize: Math.max(18, Math.min(root.fontSize,
        Math.floor((height - 56 - 48) / (1 + rows.length) / 1.35)))

      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "workspace-watermark"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}

      onWorkspaceChanged: if (root.flashOnSwitch && workspace) flashAnimation.restart()

      Connections {
        target: root
        function onFlashRequested() { if (panel.workspace) flashAnimation.restart() }
      }

      SequentialAnimation {
        id: flashAnimation
        PropertyAction { target: panel; property: "flash"; value: 1 }
        PauseAnimation { duration: Math.max(0, root.flashDuration - 800) }
        NumberAnimation {
          target: panel
          property: "flash"
          to: 0
          duration: Math.min(800, root.flashDuration)
          easing.type: Easing.InQuad
        }
      }

      // Stay mapped and fade the content instead: remapping would restack the
      // layer above notifications and menus that were mapped before it.
      Item {
        anchors.fill: parent
        opacity: root.shown && panel.workspace ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        // Dims the screen behind the text while it flashes, if set.
        Rectangle {
          anchors.fill: parent
          color: Color.background
          opacity: root.backdropOpacity * panel.flash
        }

        Rectangle {
          anchors.fill: parent
          visible: root.frame
          color: "transparent"
          border.width: root.frameWidth
          border.color: Qt.rgba(panel.hue.r, panel.hue.g, panel.hue.b, root.frameOpacity)
          Behavior on border.color { ColorAnimation { duration: 250 } }
        }

        Column {
          id: label
          spacing: 0
          opacity: panel.restOpacity + (1 - panel.restOpacity) * panel.flash

          // Clear the bar at the top and editor status bars at the bottom.
          anchors.top: panel.atTop ? parent.top : undefined
          anchors.bottom: panel.atTop ? undefined : parent.bottom
          anchors.left: panel.atLeft ? parent.left : undefined
          anchors.right: panel.atLeft ? undefined : parent.right
          anchors.topMargin: 56
          anchors.bottomMargin: 48
          anchors.leftMargin: panel.margin
          anchors.rightMargin: panel.margin

          Text {
            anchors.left: panel.atLeft ? parent.left : undefined
            anchors.right: panel.atLeft ? undefined : parent.right
            width: Math.min(implicitWidth, panel.maxWidth)
            elide: Text.ElideRight
            text: panel.project ? panel.number + " · " + panel.project : panel.number
            color: panel.hue
            font.family: Style.font.family
            font.pixelSize: panel.textSize
            font.weight: Font.Black
          }

          Repeater {
            model: panel.rows

            Row {
              required property var modelData
              anchors.left: panel.atLeft ? parent.left : undefined
              anchors.right: panel.atLeft ? undefined : parent.right
              spacing: panel.textSize * 0.4

              Text {
                id: appText
                width: Math.min(implicitWidth, panel.maxWidth)
                elide: Text.ElideRight
                text: modelData.app
                color: panel.hue
                font.family: Style.font.family
                font.pixelSize: panel.textSize
                font.weight: Font.Bold
              }

              Text {
                visible: text !== "" && width > panel.textSize
                width: Math.max(0, Math.min(implicitWidth, panel.maxWidth - appText.width - parent.spacing))
                elide: Text.ElideRight
                text: modelData.detail
                color: panel.hue
                opacity: 0.75
                font.family: Style.font.family
                font.pixelSize: panel.textSize
              }
            }
          }
        }
      }
    }
  }
}
