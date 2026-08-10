import Quickshell

ShellRoot {
    // One bar per monitor. Variants is Quickshell's Repeater equivalent for
    // non-Item objects; each instance gets `modelData` set to a screen.
    Variants {
        model: Quickshell.screens

        Bar {}
    }

    Variants {
        model: Quickshell.screens

        Desktop {}
    }

    Variants {
        model: Quickshell.screens

        NotifPopups {}
    }
}
