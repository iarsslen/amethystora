/* The workspaces in the top bar, in the colours of {{ theme_name }}: the one you are on filled with the accent,
   one with windows in the text colour, an empty one fainter */

.amethystora-workspaces-label.amethystora-workspaces-active {
  background-color: {{ accent }};
  color: {{ background }};
}

.amethystora-workspaces-label.amethystora-workspaces-busy {
  color: rgba({{ foreground_rgb }}, 0.7);
}

.amethystora-workspaces-label.amethystora-workspaces-empty {
  color: rgba({{ foreground_rgb }}, 0.4);
}

/* A label being dragged, on the theme's background; the one you are on keeps its accent */
.amethystora-workspaces-dragged.amethystora-workspaces-busy,
.amethystora-workspaces-dragged.amethystora-workspaces-empty {
  background-color: {{ background }};
}
