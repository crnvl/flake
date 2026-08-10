import Quickshell
import Quickshell.Wayland
import QtQuick

// Full-screen TUI dashboard on the background layer -- a wallpaper that shows
// you something. It sits below every niri window, so it's what you see on an
// empty workspace and in the overview.
//
// Composed on a 110-column grid so the panels line up into a single block
// rather than floating independently.
PanelWindow {
    id: desk

    property var modelData

    screen: desk.modelData
    color: Theme.bg

    // Below normal windows. WlrLayer.Background also puts it beneath the
    // Bottom layer, which is where most wallpaper tools sit.
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "quickshell-desktop"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Empty input region: the dashboard is purely decorative and must never
    // swallow a click.
    mask: Region {}

    // Minute precision on purpose -- repainting five rows of huge glyphs once
    // a second would be a silly thing to do on a wallpaper.
    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    readonly property int gridCols: 110
    readonly property int halfCols: 54
    readonly property int gapCols: 2

    Column {
        anchors.centerIn: parent
        spacing: Theme.row

        // ── Row 1: identity + memory ─────────────────────────────────────
        Row {
            spacing: Theme.cell * desk.gapCols

            Box {
                cols: desk.halfCols
                rowCount: 4
                title: "SYSTEM"

                Column {
                    x: Theme.cell
                    spacing: 0

                    Field {
                        label: "host"
                        value: Sys.host
                    }

                    Field {
                        label: "kernel"
                        value: Sys.kernel
                    }

                    Field {
                        label: "nixos"
                        value: Sys.nixos
                    }

                    Field {
                        label: "uptime"
                        value: Sys.fmtUptime(Sys.uptime)
                    }
                }
            }

            Box {
                cols: desk.halfCols
                rowCount: 4
                title: "MEMORY"

                Column {
                    x: Theme.cell
                    spacing: 0

                    Row {
                        height: Theme.row

                        Txt {
                            text: Theme.padTo("ram", 9)
                            color: Theme.dim
                            height: Theme.row
                        }

                        Meter {
                            value: Sys.memFrac
                            cells: 20
                        }

                        Txt {
                            text: Theme.padLeft(Math.round(Sys.memFrac * 100) + "%", 5)
                            height: Theme.row
                        }
                    }

                    Field {
                        label: ""
                        value: Sys.fmtBytes(Sys.memUsed) + " / " + Sys.fmtBytes(Sys.memTotal)
                        muted: true
                    }

                    Row {
                        height: Theme.row

                        Txt {
                            text: Theme.padTo("swap", 9)
                            color: Theme.dim
                            height: Theme.row
                        }

                        Meter {
                            value: Sys.swapFrac
                            cells: 20
                        }

                        Txt {
                            text: Theme.padLeft(Math.round(Sys.swapFrac * 100) + "%", 5)
                            height: Theme.row
                        }
                    }

                    Field {
                        label: ""
                        value: Sys.fmtBytes(Sys.swapUsed) + " / " + Sys.fmtBytes(Sys.swapTotal)
                        muted: true
                    }
                }
            }
        }

        // ── Centrepiece: clock ───────────────────────────────────────────
        Item {
            width: Theme.cell * desk.gridCols
            height: bigClock.implicitHeight + Theme.row * 2

            BigClock {
                id: bigClock

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                time: Qt.formatDateTime(clock.date, "hh:mm")
            }

            Txt {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: bigClock.bottom
                anchors.topMargin: Theme.row / 2
                text: Qt.formatDateTime(clock.date, "yyyy-MM-dd  dddd")
                color: Theme.dim
            }
        }

        // ── CPU ──────────────────────────────────────────────────────────
        Box {
            cols: desk.gridCols
            rowCount: 5
            title: "CPU"

            Column {
                x: Theme.cell
                spacing: 0

                Row {
                    height: Theme.row

                    Spark {
                        values: Cpu.history
                        cells: 48
                    }

                    Txt {
                        text: "  avg " + Theme.padLeft(Math.round(Cpu.usage * 100) + "%", 4)
                        color: Theme.dim
                        height: Theme.row
                    }
                }

                Item {
                    width: 1
                    height: Theme.row
                }

                Grid {
                    columns: 4
                    spacing: 0

                    Repeater {
                        model: Cpu.cores

                        Item {
                            required property int index
                            required property real modelData

                            width: Theme.cell * 26
                            height: Theme.row

                            Row {
                                spacing: 0

                                Txt {
                                    text: Theme.padLeft(String(index), 2) + " "
                                    color: Theme.dim
                                    height: Theme.row
                                }

                                Meter {
                                    value: modelData
                                    cells: 10
                                }

                                Txt {
                                    text: Theme.padLeft(Math.round(modelData * 100) + "%", 5)
                                    height: Theme.row
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Row 3: disk + network ────────────────────────────────────────
        Row {
            spacing: Theme.cell * desk.gapCols

            Box {
                cols: desk.halfCols
                rowCount: 3
                title: "DISK"

                Column {
                    x: Theme.cell
                    spacing: 0

                    Row {
                        height: Theme.row

                        Txt {
                            text: Theme.padTo("/", 9)
                            color: Theme.dim
                            height: Theme.row
                        }

                        Meter {
                            value: Sys.diskFrac
                            cells: 20
                        }

                        Txt {
                            text: Theme.padLeft(Math.round(Sys.diskFrac * 100) + "%", 5)
                            height: Theme.row
                        }
                    }

                    Field {
                        label: ""
                        value: Sys.fmtBytes(Sys.diskUsed) + " / " + Sys.fmtBytes(Sys.diskTotal)
                        muted: true
                    }

                    Field {
                        label: "free"
                        value: Sys.fmtBytes(Sys.diskTotal - Sys.diskUsed)
                    }
                }
            }

            Box {
                cols: desk.halfCols
                rowCount: 3
                title: "NETWORK"

                Column {
                    x: Theme.cell
                    spacing: 0

                    Field {
                        label: Network.vpn ? "vpn" : "link"
                        value: Network.wifi ? Network.ssid : (Network.connected ? "wired" : "offline")
                        muted: !Network.connected
                    }

                    Field {
                        label: "rx"
                        value: Sys.fmtRate(Sys.rxRate)
                    }

                    Field {
                        label: "tx"
                        value: Sys.fmtRate(Sys.txRate)
                    }
                }
            }
        }
    }
}
