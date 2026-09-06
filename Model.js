.pragma library

var GLYPH = {
  mobile: String.fromCodePoint(0xf011c),
  tablet: String.fromCodePoint(0xf0e70),
  laptop: String.fromCodePoint(0xf0322),
  desktop: String.fromCodePoint(0xf0379),
  server: String.fromCodePoint(0xf048b),
  headless: String.fromCodePoint(0xf048b),
  web: String.fromCodePoint(0xf059f),
  accessPoint: String.fromCodePoint(0xf0003),
  trayUp: String.fromCodePoint(0xf011d),
  trayDown: String.fromCodePoint(0xf0120),
  clipboard: String.fromCodePoint(0xf0c57),
  send: String.fromCodePoint(0xf0552),
  receive: String.fromCodePoint(0xf01da),
  done: String.fromCodePoint(0xf012c),
  failed: String.fromCodePoint(0xf0156),
  stop: String.fromCodePoint(0xf0156),
  refresh: String.fromCodePoint(0xf0450),
  folder: String.fromCodePoint(0xf0770)
}

function deviceGlyph(type) {
  var key = String(type || "desktop").toLowerCase()
  return GLYPH[key] || GLYPH.desktop
}

function formatBytes(bytes) {
  var value = Number(bytes)
  if (!isFinite(value) || value <= 0) return "0 B"
  var units = ["B", "KB", "MB", "GB", "TB"]
  var index = 0
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024
    index += 1
  }
  var digits = value >= 100 || index === 0 ? 0 : 1
  return value.toFixed(digits) + " " + units[index]
}

function modeSummary(mode, receiving) {
  if (mode === "off") return "Receiving off"
  if (!receiving) return "Discoverable, but the port is busy"
  return mode === "auto" ? "Everyone nearby can send" : "Asks before receiving"
}

function deviceMeta(device) {
  if (!device) return ""
  var model = String(device.deviceModel || "").trim()
  var parts = []
  if (model !== "") parts.push(model)
  parts.push(String(device.ip || ""))
  return parts.join(" · ")
}

function transferGlyph(transfer) {
  if (!transfer) return GLYPH.send
  if (transfer.status === "done") return GLYPH.done
  if (transfer.status === "failed" || transfer.status === "declined"
      || transfer.status === "expired" || transfer.status === "cancelled")
    return GLYPH.failed
  return transfer.direction === "receive" ? GLYPH.receive : GLYPH.send
}

function transferTitle(transfer) {
  if (!transfer) return ""
  var count = Number(transfer.files || 1)
  var name = String(transfer.fileName || "file")
  return count > 1 ? name + " +" + (count - 1) + " more" : name
}

function transferMeta(transfer) {
  if (!transfer) return ""
  var peer = String(transfer.peer || "device")
  var direction = transfer.direction === "receive" ? "from " : "to "
  if (transfer.status === "failed") return String(transfer.error || "Failed") 
  if (transfer.status === "declined") return "Declined"
  if (transfer.status === "expired") return "Expired — nobody answered in time"
  if (transfer.status === "cancelled") return "Cancelled"
  if (transfer.status === "done")
    return formatBytes(transfer.total) + " " + direction + peer
  return formatBytes(transfer.bytes) + " of " + formatBytes(transfer.total) + " " + direction + peer
}

function progress(transfer) {
  if (!transfer) return 0
  var total = Number(transfer.total || 0)
  if (total <= 0) return 0
  if (transfer.status === "done") return 1
  return Math.max(0, Math.min(1, Number(transfer.bytes || 0) / total))
}

function incomingTitle(incoming) {
  if (!incoming) return ""
  var count = Number(incoming.fileCount || 1)
  return String(incoming.alias || "A device") + " wants to send "
    + count + (count === 1 ? " file" : " files")
}

function secondsLeft(incoming, timeout, now) {
  if (!incoming) return 0
  var deadline = Number(incoming.requested || 0) + Number(timeout || 60)
  return Math.max(0, Math.round(deadline - now / 1000))
}

function incomingMeta(incoming) {
  if (!incoming) return ""
  var names = (incoming.names || []).join(", ")
  var size = formatBytes(incoming.totalSize)
  return names === "" ? size : size + " · " + names
}
