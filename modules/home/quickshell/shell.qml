import Quickshell

ShellRoot {
    // One bar per monitor. Variants is Quickshell's Repeater equivalent for
    // non-Item objects; each instance gets `modelData` set to a screen.
    Variants {
        model: Quickshell.screens

        Bar {}
    }

    // Single OSD, on the default screen.
    Osd {}
}
