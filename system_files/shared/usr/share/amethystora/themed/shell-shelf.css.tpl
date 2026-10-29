/* The shelf in the colours of {{ theme_name }} (modules/shelf.js): the glow at the screen's edge in the accent, from
   nothing to 0.7 across it with a glow of the accent at 0.6, and the text of the card a shake opens. The shelf's window
   follows the theme itself (amethystora-shelf). */

#uiGroup .amethystora-shelf-glow {
  background-gradient-start: rgba({{ accent_bg_rgb }}, 0);
  background-gradient-end: rgba({{ accent_bg_rgb }}, 0.7);
  box-shadow: -6px 0 24px rgba({{ accent_bg_rgb }}, 0.6);
}

#uiGroup .amethystora-shelf-glow.amethystora-shelf-glow-start {
  background-gradient-start: rgba({{ accent_bg_rgb }}, 0.7);
  background-gradient-end: rgba({{ accent_bg_rgb }}, 0);
  box-shadow: 6px 0 24px rgba({{ accent_bg_rgb }}, 0.6);
}

#uiGroup .amethystora-shelf-card {
  color: {{ foreground }};
}
