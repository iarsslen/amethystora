/* Focus profiles in the colours of {{ theme_name }} (modules/focus.js): the Focus tile a tint of the text colour over
   the glass with a ring of the accent's text colour, the chosen chip filled with the text colour and its word in the
   background's, the lines' dots and Edit in Control in the accent's text colour, the dimmed words at the board's
   strength; and the profile's mark in the live pill on the accent's plate. The selectors start from the shell's top
   group and name quick settings twice, so that they win over the quick settings' own and the glass's tints. */

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-block.amethystora-focus-tile {
  background-color: rgba({{ foreground_rgb }}, 0.07);
  border-color: rgba({{ accent_text_rgb }}, 0.35);
  color: {{ foreground }};
}

#uiGroup .quick-settings.amethystora-quick .amethystora-focus-state,
#uiGroup .quick-settings.amethystora-quick .amethystora-focus-ends-label,
#uiGroup .quick-settings.amethystora-quick .amethystora-focus-ends-dot,
#uiGroup .quick-settings.amethystora-quick .amethystora-focus-end {
  color: rgba({{ foreground_rgb }}, 0.85);
}

#uiGroup .quick-settings.amethystora-quick .amethystora-focus-end:hover,
#uiGroup .quick-settings.amethystora-quick .amethystora-focus-end:checked {
  color: {{ foreground }};
}

#uiGroup .quick-settings.amethystora-quick .amethystora-focus-chip {
  background-color: rgba({{ foreground_rgb }}, 0.10);
  color: {{ foreground }};
}

#uiGroup .quick-settings.amethystora-quick .amethystora-focus-chip:hover {
  background-color: rgba({{ foreground_rgb }}, 0.16);
}

#uiGroup .quick-settings.amethystora-quick .amethystora-focus-chip:checked {
  background-color: {{ foreground }};
  color: {{ background }};
}

#uiGroup .quick-settings.amethystora-quick .amethystora-focus-chip:focus {
  box-shadow: 0 0 0 2px {{ accent_text }};
}

#uiGroup .quick-settings.amethystora-quick .amethystora-focus-dot {
  background-color: {{ accent_text }};
}

#uiGroup .quick-settings.amethystora-quick .amethystora-focus-line-text {
  color: rgba({{ foreground_rgb }}, 0.9);
}

#uiGroup .quick-settings.amethystora-quick .amethystora-focus-edit {
  color: {{ accent_text }};
}

#uiGroup .quick-settings.amethystora-quick .amethystora-focus-edit:hover {
  color: {{ foreground }};
}

/* The mark: the pill's plate in the accent, as the board's */

#uiGroup .amethystora-pill-plate-focus .amethystora-pill-piece {
  background-color: rgba({{ accent_bg_rgb }}, 0.6);
}
