{ config, ... }:

{
    programs.niri.settings = {
        binds = {
            "Mod+Shift+Slash".hotkey-overlay.hidden = true;

            "Mod+T".action.spawn = "alacritty";
            "MOD+D".action.spawn = "fuzzel";

            "Mod+O".action.toggle-overview = true;
            "Mod+Q".action.close-window = true;

            "Mod+Left".action.focus-column-left = true;
            "Mod+Right".action.focus-column-right = true;
            "Mod+Up".action.focus-window-up = true;
            "Mod+Down".action.focus-window-down = true;

            "Mod+Ctrl+Left".action.move-column-left = true;
            "Mod+Ctrl+Right".action.move-column-right = true;
            "Mod+Ctrl+Up".action.move-window-up = true;
            "Mod+Ctrl+Down".action.move-window-down = true;

            "Mod+Shift+Ctrl+Left".action.move-column-to-monitor-left = true;
            "Mod+Shift+Ctrl+Right".action.move-column-to-monitor-right = true;
            "Mod+Shift+Ctrl+Up".action.move-window-to-monitor-up = true;
            "Mod+Shift+Ctrl+Down".action.move-window-to-monitor-down = true;

            "Mod+1".action.focus-workspace = 1;
            "Mod+2".action.focus-workspace = 2;
            "Mod+3".action.focus-workspace = 3;
            "Mod+4".action.focus-workspace = 4;
            "Mod+5".action.focus-workspace = 5;
            "Mod+6".action.focus-workspace = 6;
            "Mod+7".action.focus-workspace = 7;
            "Mod+8".action.focus-workspace = 8;
            "Mod+9".action.focus-workspace = 9;
            
            "Mod+Ctrl+1".action.move-column-to-workspace = 1;
            "Mod+Ctrl+2".action.move-column-to-workspace = 2;
            "Mod+Ctrl+3".action.move-column-to-workspace = 3;
            "Mod+Ctrl+4".action.move-column-to-workspace = 4;
            "Mod+Ctrl+5".action.move-column-to-workspace = 5;
            "Mod+Ctrl+6".action.move-column-to-workspace = 6;
            "Mod+Ctrl+7".action.move-column-to-workspace = 7;
            "Mod+Ctrl+8".action.move-column-to-workspace = 8;
            "Mod+Ctrl+9".action.move-column-to-workspace = 9;

            "Mod+F".action.maximize-column = true;
            "Mod+Shift+F".action.fullscreen-window = true;

            "Mod+V".action.toggle-window-floating = true;
        };
    };
}