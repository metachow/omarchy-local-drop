import QtQuick
import Quickshell
import Quickshell.Io

// Owns the local-dropd process, mirrors its state file into QML properties, and
// funnels every panel action through one serialized `local-drop-ctl` queue so two
// clicks in quick succession can't race each other.
Item {
  id: root

  property string daemonPath: ""
  property string ctlPath: ""
  readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-local-drop"

  property bool daemonRunning: false
  property bool online: false
  property string deviceName: ""
  property string fingerprint: ""
  property string receiveMode: "ask"
  property bool receiving: false
  property string saveDir: ""
  property real askTimeout: 60
  property string daemonError: ""
  property var devices: []
  property var transfers: []
  property var incoming: null
  property string actionStatus: ""
  property bool active: false          // panel open — poll harder while it is

  // Files chosen in the portal are held here until the picker exits, then sent
  // to whichever device row started the flow.
  property string pendingFingerprint: ""
  // A device whose pick is waiting for a previous chooser to actually exit.
  property var pendingPick: null

  readonly property bool busy: ctlProcess.running || picker.running
  readonly property bool hasIncoming: incoming !== null && incoming !== undefined

  property var _queue: []

  signal sendStarted(string alias)

  function apply(raw) {
    try {
      var state = JSON.parse(String(raw || "{}"))
      if (!state || typeof state !== "object") return
      online = true
      deviceName = String(state.alias || "")
      fingerprint = String(state.fingerprint || "")
      receiveMode = String(state.receiveMode || "ask")
      receiving = state.receiving === true
      saveDir = String(state.saveDir || "")
      askTimeout = Number(state.askTimeout || 60)
      daemonError = String(state.error || "")
      devices = state.devices || []
      transfers = state.transfers || []
      incoming = state.incoming || null
    } catch (e) {
      online = false
    }
  }

  function reloadState() { stateFile.reload() }

  function enqueue(args) {
    _queue = _queue.concat([args])
    pump()
  }

  function pump() {
    if (ctlProcess.running || _queue.length === 0 || ctlPath === "") return
    var next = _queue[0]
    _queue = _queue.slice(1)
    ctlProcess.command = [ctlPath].concat(next)
    ctlProcess.running = true
  }

  function setMode(mode) { enqueue(["mode", mode]) }
  function toggleReceiving() { setMode(receiveMode === "off" ? "ask" : "off") }
  function announce() { enqueue(["announce"]) }
  function cancelTransfer(id) { enqueue(["cancel", String(id || "")]) }
  function clearTransfers() { enqueue(["clear"]) }

  function respond(accept) {
    if (!hasIncoming) return
    enqueue([accept ? "accept" : "decline", String(incoming.sessionId || "")])
  }

  function sendTo(deviceFingerprint, files) {
    if (!deviceFingerprint || !files || files.length === 0) return
    enqueue(["send", deviceFingerprint].concat(files))
  }

  function sendClipboard(device) {
    if (!device) return
    enqueue(["send-clipboard", String(device.fingerprint || "")])
    note("Sending the clipboard to " + String(device.alias || "device") + "…")
  }

  function pickAndSend(device) {
    if (!device) return
    if (picker.running) {
      // A chooser is still up, or died in a way Quickshell has not noticed yet.
      // Silently returning here left the send button dead until the next shell
      // restart, so wind the old one down and start this pick when it exits.
      pendingPick = device
      picker.running = false
      return
    }
    startPicker(device)
  }

  function startPicker(device) {
    pendingFingerprint = String(device.fingerprint || "")
    actionStatus = "Choosing files for " + String(device.alias || "device") + "…"
    // StdioCollector.text is read-only and refills itself on the next run;
    // assigning to it threw, and the throw took the two lines below with it.
    picker.command = ["omarchy-file-select", "--title",
                      "LocalDrop to " + String(device.alias || "device"), "--multiple"]
    picker.running = true
  }

  function openSaveDir() {
    if (saveDir === "") return
    Quickshell.execDetached(["uwsm-app", "--", "xdg-open", saveDir])
  }

  function note(text, keep) {
    actionStatus = text
    if (!keep) statusTimer.restart()
  }

  Process {
    id: daemonProcess
    command: root.daemonPath === "" ? [] : [root.daemonPath]
    running: root.daemonPath !== ""
    onRunningChanged: root.daemonRunning = running
    stderr: SplitParser {
      onRead: function(line) {
        var text = String(line || "").trim()
        if (text !== "") console.warn("local-drop", text)
      }
    }
    onExited: function(exitCode) {
      root.online = false
      // The shell outlives any single daemon crash; come back after a beat.
      restartTimer.restart()
    }
  }

  Timer {
    id: restartTimer
    interval: 3000
    onTriggered: if (!daemonProcess.running && root.daemonPath !== "") daemonProcess.running = true
  }

  FileView {
    id: stateFile
    path: root.runtimeDir + "/state.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.apply(text())
    onLoadFailed: root.online = false
  }

  // The daemon rewrites state.json by rename, which some filesystem watchers
  // stop following; a cheap poll keeps the panel honest either way.
  Timer {
    interval: root.active || root.hasIncoming ? 700 : 2500
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.reloadState()
  }

  Process {
    id: ctlProcess
    running: false
    command: []
    stdout: StdioCollector { id: ctlOut; waitForEnd: true }
    stderr: StdioCollector { id: ctlErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var message = String(ctlErr.text || ctlOut.text || "").trim()
        if (message !== "") root.note(message.substring(0, 140))
      }
      root.reloadState()
      Qt.callLater(root.pump)
    }
  }

  Process {
    id: picker
    running: false
    command: []
    stdout: StdioCollector { id: pickedFiles; waitForEnd: true }
    onExited: function(exitCode) {
      var target = root.pendingFingerprint
      root.pendingFingerprint = ""
      if (root.pendingPick) {
        var next = root.pendingPick
        root.pendingPick = null
        Qt.callLater(function() { root.startPicker(next) })
        return
      }
      if (exitCode > 1) { root.note("The file chooser did not open"); return }
      var files = String(pickedFiles.text || "").split("\n").filter(function(line) {
        return String(line).trim() !== ""
      })
      if (exitCode !== 0 || files.length === 0) { root.actionStatus = ""; return }
      root.sendTo(target, files)
      root.note("Sending " + files.length + " file" + (files.length === 1 ? "" : "s") + "…")
    }
  }

  Timer {
    id: statusTimer
    interval: 3200
    onTriggered: root.actionStatus = ""
  }
}
