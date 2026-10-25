/* The palette of {{ theme_name }} for the GTK 3 applications that draw with adw-gtk3: the named colours it shares with
   libadwaita, in the same values as palette-gtk4.css. The Amethystora GTK theme (Sweet, for the two Amethystora
   themes) names its colours otherwise and keeps its own. 20-gtk-apps.sh puts this file at the top of
   ~/.config/gtk-3.0/gtk.css, unless High Contrast is on. */

@define-color window_bg_color {{ window_bg }};
@define-color window_fg_color {{ foreground }};
@define-color view_bg_color {{ view_bg }};
@define-color view_fg_color {{ foreground }};
@define-color headerbar_bg_color {{ headerbar_bg }};
@define-color headerbar_fg_color {{ foreground }};
@define-color headerbar_backdrop_color {{ window_bg }};
@define-color sidebar_bg_color {{ sidebar_bg }};
@define-color sidebar_fg_color {{ foreground }};
@define-color sidebar_backdrop_color {{ window_bg }};
@define-color card_bg_color {{ card_bg }};
@define-color card_fg_color {{ foreground }};
@define-color dialog_bg_color {{ dialog_bg }};
@define-color dialog_fg_color {{ foreground }};
@define-color popover_bg_color {{ popover_bg }};
@define-color popover_fg_color {{ foreground }};
@define-color thumbnail_bg_color {{ card_bg }};
@define-color thumbnail_fg_color {{ foreground }};

@define-color accent_bg_color {{ accent_bg }};
@define-color accent_fg_color {{ accent_fg }};
@define-color accent_color {{ accent_text }};
@define-color destructive_bg_color {{ destructive_bg }};
@define-color destructive_fg_color {{ destructive_fg }};
@define-color destructive_color {{ destructive_text }};
@define-color success_bg_color {{ success_bg }};
@define-color success_fg_color {{ success_fg }};
@define-color success_color {{ success_text }};
@define-color warning_bg_color {{ warning_bg }};
@define-color warning_fg_color {{ warning_fg }};
@define-color warning_color {{ warning_text }};
@define-color error_bg_color {{ error_bg }};
@define-color error_fg_color {{ error_fg }};
@define-color error_color {{ error_text }};

.dim-label {
    opacity: {{ dim_alpha }};
}
