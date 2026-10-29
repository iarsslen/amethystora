/* Widgets on the desktop in the colours of {{ theme_name }}: glass cards over the wallpaper in the theme's text colour,
   the lines after the first a little dimmer; the theme's popover colour where the glass is solid or not running. */

#uiGroup .amethystora-deskwidgets-card {
  background-color: rgba({{ popover_bg_rgb }}, 0.9);
  border-color: rgba({{ foreground_rgb }}, 0.16);
  color: {{ foreground }};
}

#uiGroup .amethystora-deskwidgets-card.amethystora-glass-pane {
  background-color: transparent;
  border-color: transparent;
  -amethystora-glass-edge: rgba({{ foreground_rgb }}, 0.16);
}

#uiGroup.amethystora-glass-solid .amethystora-deskwidgets-card.amethystora-glass-pane {
  background-color: {{ popover_bg }};
}

#uiGroup .amethystora-deskwidgets-line {
  color: rgba({{ foreground_rgb }}, 0.78);
}
