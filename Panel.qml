import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// LocalDrop for the Omarchy bar: nearby devices, a click to send, and an
// explicit accept step for anything arriving. Everything on screen comes from
// the state file local-dropd publishes; every button posts one control command.
Panel {
  id: root
  moduleName: "zhou-mi.local-drop"
  ipcTarget: "zhou-mi.local-drop"
  manageIpc: false

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool sharing: service.receiveMode !== "off"
  readonly property bool alerting: service.hasIncoming
  readonly property bool transferring: {
    var list = service.transfers || []
    for (var i = 0; i < list.length; i++)
      if (list[i].status === "active") return true
    return false
  }
  // One glyph per state: broadcasting normally, an inbound tray while a request
  // is waiting, an outbound one while bytes are moving.
  readonly property string barGlyph: {
    if (alerting) return Model.GLYPH.trayDown
    if (transferring) return Model.GLYPH.trayUp
    return Model.GLYPH.accessPoint
  }

  // -1 is the incoming card, 0..n-1 the device rows.
  property int cursorIndex: 0
  property bool cursorActive: false
  // Ticks only while a request is on screen, to drive its countdown.
  property real nowMs: 0

  Timer {
    interval: 500
    repeat: true
    running: root.opened && service.hasIncoming
    triggeredOnStart: true
    onTriggered: root.nowMs = Date.now()
  }

  function deviceCount() { return (service.devices || []).length }

  function ensureCursor() {
    var min = service.hasIncoming ? -1 : 0
    if (cursorIndex < min) cursorIndex = min
    if (cursorIndex > deviceCount() - 1) cursorIndex = Math.max(min, deviceCount() - 1)
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) return
    cursorIndex += dy > 0 ? 1 : -1
    ensureCursor()
  }

  // Shared by the two IPC verbs: `omarchy-shell zhou-mi.local-drop send <fp>`
  // opens the file chooser for that device, `clipboard <fp>` skips it.
  function actOnDevice(fingerprint, useClipboard) {
    var list = service.devices || []
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].fingerprint || "") !== String(fingerprint)) continue
      if (useClipboard) service.sendClipboard(list[i])
      else service.pickAndSend(list[i])
      return "ok"
    }
    return "no device with that fingerprint is nearby"
  }

  function cursorDevice() {
    var list = service.devices || []
    if (cursorIndex < 0 || cursorIndex >= list.length) return null
    return list[cursorIndex]
  }

  function clipboardToCursor() {
    var device = cursorDevice()
    if (device) service.sendClipboard(device)
  }

  function activateCursor() {
    ensureCursor()
    if (cursorIndex === -1) { service.respond(true); return }
    var list = service.devices || []
    if (cursorIndex >= 0 && cursorIndex < list.length) service.pickAndSend(list[cursorIndex])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    service.active = opened
    if (opened) {
      cursorActive = false
      cursorIndex = service.hasIncoming ? -1 : 0
      if (panelFlick) panelFlick.contentY = 0
      service.reloadState()
      service.announce()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  Service {
    id: service
    daemonPath: root.pluginDir + "local-dropd"
    ctlPath: root.pluginDir + "local-drop-ctl"
  }

  Connections {
    target: service
    function onIncomingChanged() {
      if (service.hasIncoming && root.opened) { root.cursorActive = true; root.cursorIndex = -1 }
      root.ensureCursor()
    }
    function onDevicesChanged() { root.ensureCursor() }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function accept(): string { service.respond(true); return "ok" }
    function decline(): string { service.respond(false); return "ok" }
    function mode(value: string): string { service.setMode(value); return value }
    function send(fingerprint: string): string { return root.actOnDevice(fingerprint, false) }
    function clipboard(fingerprint: string): string { return root.actOnDevice(fingerprint, true) }
    function status(): string { return Model.modeSummary(service.receiveMode, service.receiving) }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barGlyph
    dimmed: !root.sharing && !root.alerting && !root.transferring
    active: root.alerting
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) service.toggleReceiving()
      else if (buttonCode === Qt.MiddleButton) service.announce()
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
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var key = String(t || "").toLowerCase()
        if (key === "a") service.respond(true)
        else if (key === "x") service.respond(false)
        else if (key === "r") service.announce()
        else if (key === "v") root.clipboardToCursor()
        else if (key === "o") service.openSaveDir()
        else if (key === "c") service.clearTransfers()
        else if (key === "1") service.setMode("off")
        else if (key === "2") service.setMode("ask")
        else if (key === "3") service.setMode("auto")
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight

            PanelHero {
              id: hero
              width: parent.width
              title: "LocalDrop"
              meta: service.online
                ? Model.modeSummary(service.receiveMode, service.receiving)
                : "Starting…"
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: root.sharing ? 1.0 : 0.5
              iconComponent: Component {
                Text {
                  textFormat: Text.PlainText
                  text: root.barGlyph
                  color: root.sharing ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }

              trailingControl: Component {
                ToggleSwitch {
                  id: receiveSwitch
                  checked: root.sharing
                  hasCursor: false
                  foreground: hero.foreground
                  onToggled: service.toggleReceiving()

                  PanelToolTip {
                    visible: receiveSwitch.containsMouse
                    text: root.sharing ? "Stop receiving" : "Start receiving"
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            text: service.actionStatus !== "" ? service.actionStatus : service.daemonError
            color: service.actionStatus === "" && service.daemonError !== "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // ------------------------------------------------- incoming request
          IncomingCard {
            visible: service.hasIncoming
            width: parent.width
          }

          ButtonGroup {
            id: modeGroup
            width: parent.width
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            focusable: false
            options: [
              { value: "off", label: "Off" },
              { value: "ask", label: "Ask first" },
              { value: "auto", label: "Everyone" }
            ]
            value: service.receiveMode
            onChanged: function(value) { service.setMode(value) }
          }

          PanelSeparator { foreground: root.foreground }

          // -------------------------------------------------- nearby devices
          Column {
            width: parent.width
            spacing: Style.space(10)

            Item {
              width: parent.width
              implicitHeight: nearbyHeader.implicitHeight

              PanelSectionHeader {
                id: nearbyHeader
                anchors.left: parent.left
                text: "NEARBY DEVICES"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.verticalCenter: nearbyHeader.verticalCenter
                iconText: Model.GLYPH.refresh
                tooltipText: "Look again"
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.iconSmall
                onClicked: service.announce()
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(4)
              visible: root.deviceCount() === 0

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: "Looking for nearby devices…"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: "Open LocalSend on the other device, on the same network."
                color: root.dim
                opacity: 0.75
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
              }
            }

            Column {
              id: deviceColumn
              width: parent.width
              spacing: Style.space(6)
              visible: root.deviceCount() > 0

              Repeater {
                model: service.devices
                DeviceRow {
                  required property var modelData
                  required property int index
                  width: deviceColumn.width
                  device: modelData
                  rowIndex: index
                }
              }
            }
          }

          // ------------------------------------------------------- transfers
          PanelSeparator {
            visible: (service.transfers || []).length > 0
            foreground: root.foreground
          }

          Column {
            visible: (service.transfers || []).length > 0
            width: parent.width
            spacing: Style.space(10)

            Item {
              width: parent.width
              implicitHeight: transferHeader.implicitHeight

              PanelSectionHeader {
                id: transferHeader
                anchors.left: parent.left
                text: "TRANSFERS"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.verticalCenter: transferHeader.verticalCenter
                iconText: Model.GLYPH.folder
                tooltipText: "Open " + service.saveDir
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.iconSmall
                onClicked: service.openSaveDir()
              }
            }

            Column {
              id: transferColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: service.transfers
                TransferRow {
                  required property var modelData
                  width: transferColumn.width
                  transfer: modelData
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: service.online
              ? "Visible as " + service.deviceName + " · saves to " + service.saveDir
              : "Waiting for the LocalDrop daemon…"
            color: root.dim
            opacity: 0.8
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideMiddle
          }
        }
      }
    }
  }

  // --------------------------------------------------------------- components

  component IncomingCard: CursorSurface {
    id: card
    hasCursor: root.cursorActive && root.cursorIndex === -1
    current: true
    foreground: root.urgent
    implicitHeight: cardColumn.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onEntered: { root.cursorActive = true; root.cursorIndex = -1 }
    }

    Column {
      id: cardColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: Model.incomingTitle(service.incoming)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        wrapMode: Text.WordWrap
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: Model.incomingMeta(service.incoming)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        // The request really does expire, and the sender gives up with it;
        // saying so beats a card that silently disappears.
        text: "Expires in " + Model.secondsLeft(service.incoming,
                                                service.askTimeout, root.nowMs) + "s"
        color: root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Row {
        spacing: Style.space(8)

        ActionChip {
          label: "Accept"
          emphasis: true
          onActivated: service.respond(true)
        }

        ActionChip {
          label: "Decline"
          onActivated: service.respond(false)
        }
      }
    }
  }

  component ActionChip: Rectangle {
    id: chip
    property string label: ""
    property bool emphasis: false
    signal activated()

    readonly property bool hot: chipMouse.containsMouse

    implicitWidth: chipText.implicitWidth + Style.space(22)
    implicitHeight: Style.spacing.controlHeight
    radius: Style.cornerRadius > 0 ? Style.space(6) : 0
    color: emphasis
      ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, hot ? 0.28 : 0.18)
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, hot ? 0.16 : 0.07)
    border.width: 1
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, hot ? 0.6 : 0.28)

    Text {
      id: chipText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: chip.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.activated()
    }
  }

  component DeviceRow: CursorSurface {
    id: deviceRow
    property var device: null
    property int rowIndex: 0

    hasCursor: root.cursorActive && root.cursorIndex === rowIndex
    foreground: root.foreground
    implicitHeight: deviceContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: { root.cursorActive = true; root.cursorIndex = deviceRow.rowIndex }
      onClicked: service.pickAndSend(deviceRow.device)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)

      Text {
        textFormat: Text.PlainText
        text: Model.deviceGlyph(deviceRow.device ? deviceRow.device.deviceType : "desktop")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.iconLarge
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: deviceContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: deviceRow.device ? String(deviceRow.device.alias || "Unknown device") : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: Model.deviceMeta(deviceRow.device)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: Model.GLYPH.clipboard
        tooltipText: "Send the clipboard"
        foreground: root.foreground
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: service.sendClipboard(deviceRow.device)
      }

      PanelActionButton {
        iconText: Model.GLYPH.send
        tooltipText: "Send files"
        foreground: root.foreground
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: service.pickAndSend(deviceRow.device)
      }
    }
  }

  component TransferRow: Item {
    id: transferRow
    property var transfer: null

    implicitHeight: transferContent.implicitHeight + Style.space(10)

    RowLayout {
      id: transferLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)

      PanelActionButton {
        visible: transferRow.transfer && transferRow.transfer.status === "active"
        iconText: Model.GLYPH.stop
        tooltipText: "Cancel"
        foreground: root.urgent
        fontFamily: root.fontFamily
        fontSize: Style.font.iconSmall
        Layout.alignment: Qt.AlignVCenter
        onClicked: service.cancelTransfer(transferRow.transfer.id)
      }

      Text {
        visible: !(transferRow.transfer && transferRow.transfer.status === "active")
        textFormat: Text.PlainText
        text: Model.transferGlyph(transferRow.transfer)
        color: transferRow.transfer && (transferRow.transfer.status === "failed"
          || transferRow.transfer.status === "declined") ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: transferContent
        Layout.fillWidth: true
        spacing: Style.space(3)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: Model.transferTitle(transferRow.transfer)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideMiddle
        }

        Rectangle {
          visible: transferRow.transfer && transferRow.transfer.status === "active"
          Layout.fillWidth: true
          height: Style.space(3)
          radius: height / 2
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)

          Rectangle {
            width: parent.width * Model.progress(transferRow.transfer)
            height: parent.height
            radius: parent.radius
            color: root.foreground
            Behavior on width { NumberAnimation { duration: 160 } }
          }
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: Model.transferMeta(transferRow.transfer)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }
}
