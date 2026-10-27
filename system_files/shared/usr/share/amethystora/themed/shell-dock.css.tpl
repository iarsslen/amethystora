/* The dock in the colours of {{ theme_name }}: the veil on a light theme and the wash on a tile in the text colour (dark
   on a light theme, light on a dark one), the dots and the bar of progress in the text colour, and the count's badge in
   the palette's red with the background's colour on it (the count and the bar on the apps' icons in the overview too).
   The selectors start from the shell's top group, one id more than the dock's own stylesheet has for them, which only stands in until a theme has been applied; the veil's does
   not, so that the glass's colours for the dock in the overview stay above it. */

#dash.amethystora-dock-dash.amethystora-dock-light .dash-background {
  background-color: rgba({{ foreground_rgb }}, 0.22);
  border-color: rgba({{ background_rgb }}, 0.05);
}

#uiGroup #dash.amethystora-dock-dash .dash-item-container .overview-tile:hover .overview-icon,
#uiGroup #dash.amethystora-dock-dash .dash-item-container .overview-tile:focus .overview-icon,
#uiGroup #dash.amethystora-dock-dash .dash-item-container .show-apps:hover .overview-icon,
#uiGroup #dash.amethystora-dock-dash .dash-item-container .show-apps:focus .overview-icon,
#uiGroup #dash.amethystora-dock-dash .dash-item-container .amethystora-dock-focused .overview-icon {
  background-color: rgba({{ foreground_rgb }}, 0.2);
}

#uiGroup #dash.amethystora-dock-dash .dash-separator {
  background-color: rgba({{ foreground_rgb }}, 0.1);
}

#uiGroup #dash.amethystora-dock-dash .amethystora-dock-dot {
  background-color: {{ foreground }};
}

#uiGroup .amethystora-dock-badge {
  background-color: {{ color1 }};
  color: {{ background }};
}

#uiGroup .amethystora-dock-progress {
  background-color: rgba({{ background_rgb }}, 0.45);
  border-color: rgba({{ background_rgb }}, 0.7);
}

#uiGroup .amethystora-dock-progress-fill {
  background-color: {{ foreground }};
}
