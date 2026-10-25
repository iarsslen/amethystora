/* The palette of {{ theme_name }} for the libadwaita and GTK 4 applications: libadwaita's own colour variables, on
   :root, so that every window, header bar, sidebar, card, dialog, popover and control it draws is in the theme's
   colours and not Adwaita's grey with GNOME's nearest accent. Every text pair here reads at 4.5:1 and every line a
   control is drawn with at 3:1 (palette.awk works them out from colors.toml); the surfaces are the ground mixed
   toward the text colour (or toward white, on a light theme). 20-gtk-apps.sh puts this file at the top of
   ~/.config/gtk-4.0/gtk.css, which GTK reads above every theme. It does not apply while High Contrast is on, which
   has its own colours that a palette over them would undo: the query says so, and switches live. */

@media not (prefers-contrast: more) {
    :root {
        --window-bg-color: {{ window_bg }};
        --window-fg-color: {{ foreground }};
        --view-bg-color: {{ view_bg }};
        --view-fg-color: {{ foreground }};
        --headerbar-bg-color: {{ headerbar_bg }};
        --headerbar-fg-color: {{ foreground }};
        --headerbar-backdrop-color: {{ window_bg }};
        --sidebar-bg-color: {{ sidebar_bg }};
        --sidebar-fg-color: {{ foreground }};
        --sidebar-backdrop-color: {{ window_bg }};
        --secondary-sidebar-bg-color: {{ window_bg }};
        --secondary-sidebar-fg-color: {{ foreground }};
        --secondary-sidebar-backdrop-color: {{ window_bg }};
        --card-bg-color: {{ card_bg }};
        --card-fg-color: {{ foreground }};
        --dialog-bg-color: {{ dialog_bg }};
        --dialog-fg-color: {{ foreground }};
        --popover-bg-color: {{ popover_bg }};
        --popover-fg-color: {{ foreground }};
        --thumbnail-bg-color: {{ card_bg }};
        --thumbnail-fg-color: {{ foreground }};
        --overview-bg-color: {{ window_bg }};
        --overview-fg-color: {{ foreground }};
        --active-toggle-bg-color: rgba({{ foreground_rgb }}, 0.16);
        --active-toggle-fg-color: {{ foreground }};

        --accent-bg-color: {{ accent_bg }};
        --accent-fg-color: {{ accent_fg }};
        --accent-color: {{ accent_text }};
        --destructive-bg-color: {{ destructive_bg }};
        --destructive-fg-color: {{ destructive_fg }};
        --destructive-color: {{ destructive_text }};
        --success-bg-color: {{ success_bg }};
        --success-fg-color: {{ success_fg }};
        --success-color: {{ success_text }};
        --warning-bg-color: {{ warning_bg }};
        --warning-fg-color: {{ warning_fg }};
        --warning-color: {{ warning_text }};
        --error-bg-color: {{ error_bg }};
        --error-fg-color: {{ error_fg }};
        --error-color: {{ error_text }};

        --dim-opacity: {{ dim_opacity }}%;
    }
}
