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

    // Single instance rather than one per screen: Osd has no screen binding,
    // and a volume popup mirrored onto every monitor would be noise.
    Osd {}
}
