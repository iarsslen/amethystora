/* The screenshot tools in the colours of {{ theme_name }}: the toolbar, the buttons of a picked-up mark and of the
   preview card, and the card itself on the theme's background, light or dark as the theme is, with the theme's text
   colour on them; the text field's frame and the "Copied" badge in its accent. */

#screenshot-ui .amethystora-screenshot-toolbar {
  background-color: rgba({{ background_rgb }}, 0.95);
  color: {{ foreground }};
  border: 1px solid rgba({{ foreground_rgb }}, 0.12);
}

#screenshot-ui .amethystora-screenshot-separator {
  background-color: rgba({{ foreground_rgb }}, 0.3);
}

#screenshot-ui .amethystora-screenshot-tool {
  color: {{ foreground }};
}

#screenshot-ui .amethystora-screenshot-tool:hover {
  background-color: rgba({{ foreground_rgb }}, 0.12);
}

#screenshot-ui .amethystora-screenshot-tool:checked {
  background-color: rgba({{ foreground_rgb }}, 0.24);
}

#screenshot-ui .amethystora-screenshot-tool:active {
  background-color: rgba({{ foreground_rgb }}, 0.32);
}

/* The chosen colour's ring is the colour itself, which a toolbar of the same shade would hide: a faint outline of the
   text colour round it */
#screenshot-ui .amethystora-screenshot-swatch:checked {
  box-shadow: 0 0 0 1px rgba({{ foreground_rgb }}, 0.5);
}

#screenshot-ui .amethystora-screenshot-tool:focus,
#screenshot-ui .amethystora-screenshot-swatch:focus {
  box-shadow: inset 0 0 0 2px {{ accent }};
}

#screenshot-ui .amethystora-screenshot-slider {
  color: {{ foreground }};
  -barlevel-background-color: rgba({{ foreground_rgb }}, 0.2);
  -barlevel-active-background-color: {{ accent }};
  -slider-handle-border-color: rgba({{ foreground_rgb }}, 0.3);
}

#screenshot-ui .amethystora-screenshot-round {
  color: {{ foreground }};
  background-color: {{ background }};
}

#screenshot-ui .amethystora-screenshot-round:hover {
  background-color: st-mix({{ foreground }}, {{ background }}, 12%);
}

#screenshot-ui .amethystora-screenshot-round:active {
  background-color: st-mix({{ foreground }}, {{ background }}, 24%);
}

#screenshot-ui .amethystora-screenshot-text {
  border-color: {{ accent }};
}

/* The thumbnail and a pinned picture's buttons: glass panes over the wallpaper, the theme's popover colour where the
   glass is solid or not running; the text and the buttons in the theme's text colour, Pin in the accent */

#uiGroup .amethystora-screenshot-thumb,
#uiGroup .amethystora-screenshot-pin-pill {
  background-color: rgba({{ popover_bg_rgb }}, 0.94);
  border-color: rgba({{ foreground_rgb }}, 0.16);
  color: {{ foreground }};
}

#uiGroup .amethystora-screenshot-thumb.amethystora-glass-pane,
#uiGroup .amethystora-screenshot-pin-pill.amethystora-glass-pane {
  background-color: transparent;
  border-color: transparent;
  -amethystora-glass-edge: rgba({{ foreground_rgb }}, 0.16);
}

#uiGroup.amethystora-glass-solid .amethystora-screenshot-thumb.amethystora-glass-pane,
#uiGroup.amethystora-glass-solid .amethystora-screenshot-pin-pill.amethystora-glass-pane {
  background-color: {{ popover_bg }};
}

#uiGroup .amethystora-screenshot-thumb-button,
#uiGroup .amethystora-screenshot-pin-button {
  color: {{ foreground }};
  background-color: rgba({{ foreground_rgb }}, 0.1);
}

#uiGroup .amethystora-screenshot-thumb-button:hover,
#uiGroup .amethystora-screenshot-pin-button:hover,
#uiGroup .amethystora-screenshot-pin-button:checked {
  background-color: rgba({{ foreground_rgb }}, 0.18);
}

#uiGroup .amethystora-screenshot-thumb-button:focus {
  box-shadow: inset 0 0 0 2px {{ accent }};
}

#uiGroup .amethystora-screenshot-thumb-pin,
#uiGroup .amethystora-screenshot-thumb-pin:hover {
  color: {{ accent_fg }};
  background-color: rgba({{ accent_bg_rgb }}, 0.6);
}

#uiGroup .amethystora-screenshot-badge {
  color: {{ accent_fg }};
  background-color: {{ accent_bg }};
}

#uiGroup .amethystora-screenshot-pin-ring {
  border-color: rgba({{ accent_rgb }}, 0.6);
}

#uiGroup .amethystora-screenshot-pin-through .amethystora-screenshot-pin-ring {
  border-color: rgba({{ color3_rgb }}, 0.8);
}

#uiGroup .amethystora-screenshot-pin-shared {
  color: {{ color3 }};
}
