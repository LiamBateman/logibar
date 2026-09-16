import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Column {
  id: root
  property color foreground: Color.popups.text
  property color dim: Qt.darker(foreground, 1.55)
  property string fontFamily: Style.font.family
  property var devices: []
  property string deviceName: ""
  property real speed: 0
  property string profile: ""
  property string message: ""
  property bool failed: false
  property bool loaded: false
  property bool dirty: false
  property string output: ""
  property bool collected: false
  property bool exited: false
  property int exitCode: 0
  readonly property bool busy: process.running || (!collected && !exited)
  readonly property string helper: decodeURIComponent(Qt.resolvedUrl("../logibar-mouse-settings").toString().replace(/^file:\/\//, ""))
  visible: loaded && (devices.length > 0 || message !== "")
  spacing: Style.space(10)

  function run(args) {
    if (process.running) return
    output = ""
    collected = false
    exited = false
    exitCode = 0
    process.command = ["/bin/sh", "-c", 'exec "$0" "$@"', "python3", helper].concat(args)
    process.running = true
  }
  function refresh() { run(["status"]) }
  function selectDevice(name) {
    deviceName = name
    var d = devices.find(function(d) { return d.name === name })
    var saved = d ? d.settings : null
    speed = saved ? saved.sensitivity : 0
    profile = saved ? saved.accel_profile : ""
    dirty = false
    message = saved ? "Saved for this mouse." : "Choose settings, then Apply."
    failed = false
  }
  function finish() {
    if (!collected || !exited) return
    loaded = true
    try {
      var result = JSON.parse(output)
      if (result.error || exitCode !== 0) throw new Error(result.error || "Could not change mouse settings")
      devices = result.devices || []
      var selected = devices.find(function(d) { return d.name === deviceName })
      if (devices.length > 0) selectDevice(selected ? deviceName : devices[0].name)
      else { deviceName = ""; message = "" }
      if (result.saved) message = "Applied · saved for next login"
      failed = false
    } catch (e) {
      failed = true
      message = String(e.message || e)
    }
  }
  function save() {
    run(["apply", deviceName, speed.toFixed(2), profile])
  }

  Process {
    id: process
    stdout: StdioCollector {
      onStreamFinished: { root.output = text; root.collected = true; root.finish() }
    }
    onExited: function(code) { root.exitCode = code; root.exited = true; root.finish() }
  }

  PanelSeparator { width: parent.width; foreground: root.foreground }
  PanelSectionHeader {
    width: parent.width
    text: "MOUSE SETTINGS"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }
  Column {
    width: parent.width
    spacing: Style.space(6)
    Repeater {
      model: root.devices
      Button {
        required property var modelData
        width: parent.width
        text: modelData.name.replace(/^logitech-/, "").replace(/-+/g, " ")
        selected: root.deviceName === modelData.name
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        enabled: !root.busy
        onClicked: root.selectDevice(modelData.name)
      }
    }
  }
  Column {
    width: parent.width
    visible: root.deviceName !== ""
    spacing: Style.space(8)
    enabled: !root.busy
    opacity: root.busy ? 0.5 : 1
    Text {
      width: parent.width
      text: "Pointer speed · " + Math.round((root.speed + 1) * 50) + "%"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      textFormat: Text.PlainText
    }
    PanelSlider {
      width: parent.width
      minimum: -1
      maximum: 1
      step: 0.05
      value: root.speed
      fillColor: root.foreground
      knobColor: root.foreground
      onMoved: function(v) { root.speed = Math.round(v * 100) / 100; root.dirty = true; root.message = "Unsaved changes" }
    }
    Item {
      width: parent.width
      implicitHeight: slowLabel.implicitHeight
      Text {
        id: slowLabel
        text: "Slow"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      Text {
        anchors.right: parent.right
        text: "Fast"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
    Text {
      text: "Acceleration"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
    ButtonGroup {
      options: [{value: "", label: "Default"}, {value: "flat", label: "Off"}, {value: "adaptive", label: "Adaptive"}]
      value: root.profile
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.caption
      onChanged: function(v) { root.profile = v; root.dirty = true; root.message = "Unsaved changes" }
    }
    Text {
      width: parent.width
      text: root.profile === "flat" ? "Constant speed, regardless of how fast you move." : root.profile === "adaptive" ? "Move faster to cover more distance." : "Use this mouse’s default acceleration."
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
    }
    Row {
      spacing: Style.space(8)
      Button {
        text: "Apply"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: root.dirty
        opacity: enabled ? 1 : 0.5
        onClicked: root.save()
      }
      Button {
        text: "Defaults"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: { root.speed = 0; root.profile = ""; root.dirty = true; root.message = "Unsaved changes" }
      }
    }
  }
  Text {
    width: parent.width
    text: root.busy ? "Applying…" : root.message
    color: root.failed ? Color.urgent : root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
  }
}
