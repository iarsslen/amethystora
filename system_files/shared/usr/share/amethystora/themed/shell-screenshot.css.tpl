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

#screenshot-ui .amethystora-screenshot-round,
.amethystora-screenshot-card-box .amethystora-screenshot-round {
  color: {{ foreground }};
  background-color: {{ background }};
}

#screenshot-ui .amethystora-screenshot-round:hover,
.amethystora-screenshot-card-box .amethystora-screenshot-round:hover {
  background-color: st-mix({{ foreground }}, {{ background }}, 12%);
}

#screenshot-ui .amethystora-screenshot-round:active,
.amethystora-screenshot-card-box .amethystora-screenshot-round:active {
  background-color: st-mix({{ foreground }}, {{ background }}, 24%);
}

#screenshot-ui .amethystora-screenshot-text {
  border-color: {{ accent }};
}

.amethystora-screenshot-card-box .amethystora-screenshot-card {
  border-color: {{ background }};
  background-color: {{ background }};
}

.amethystora-screenshot-card-box .amethystora-screenshot-badge {
  background-color: {{ accent }};
}
