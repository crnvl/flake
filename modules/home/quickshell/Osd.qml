import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

// Volume / brightness OSD.
//
// The media keys in modules/home/niri.nix shell out to wpctl/brightnessctl
// directly and produce no output of their own, so without this the volume and
// brightness keys would change state with zero feedback. This is the only
// thing that shows you what happened.
//
// It's also the first real job for Box.qml.
PanelWindow {
    id: root

    property string label: ""
    property real value: 0
    property bool shown: false

    // Don't fire on startup when the sources first populate.
    property bool armed: false

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real volume: root.sink && root.sink.audio ? root.sink.audio.volume : 0
    readonly property bool muted: root.sink && root.sink.audio ? root.sink.audio.muted : false

    function flash(text, v) {
        root.label = text;
        root.value = v;
        root.shown = true;
        hide.restart();
    }

    onVolumeChanged: if (root.armed)
        root.flash("VOLUME", root.volume)
    onMutedChanged: if (root.armed)
        root.flash(root.muted ? "VOLUME  MUTED" : "VOLUME", root.muted ? 0 : root.volume)

    Connections {
        target: Brightness

        function onFractionChanged() {
            if (root.armed)
                root.flash("BRIGHTNESS", Brightness.fraction);
        }
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    Timer {
        interval: 2000
        running: true
        onTriggered: root.armed = true
    }

    Timer {
        id: hide

        interval: 1600
        onTriggered: root.shown = false
    }

    visible: root.shown
    color: Theme.bg

    anchors.bottom: true
    margins.bottom: Theme.rows(4)
    exclusionMode: ExclusionMode.Ignore

    implicitWidth: box.implicitWidth
    implicitHeight: box.implicitHeight

    Box {
        id: box

        title: root.label
        cols: 34
        rowCount: 1
        frameColor: Theme.fg

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Meter {
                value: root.value
                cells: 22
            }

            Seg {
                text: Theme.padLeft(Math.round(root.value * 100) + "%", 5)
            }
        }
    }
}
