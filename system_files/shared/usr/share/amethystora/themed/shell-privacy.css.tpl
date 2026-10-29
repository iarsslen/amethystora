/* The privacy module in the colours of {{ theme_name }} (modules/privacy.js): the share guard's cover tinted with the
   background over GNOME's blur, or a card of the theme's card colour; the shield's states in the theme's success and
   warning colours, its squares and chips a tint of the text colour, Open Security in the accent's text colour; network
   by app's rows a lighter tint, their counts in the accent's text colour; walk-away lock's card on the glass's panel.
   The dimmed words are the text colour at the board's strength. */

/* The cover lives inside a window's actor, under no St ancestor: its rules name the cover itself, never #uiGroup */
.amethystora-privacy-cover.amethystora-privacy-cover-blur {
  background-color: rgba({{ background_rgb }}, 0.35);
}

/* Opaque, the card and every cover until its blur is drawn: after the tint, so that it wins while both are on */
.amethystora-privacy-cover.amethystora-privacy-cover-card,
.amethystora-privacy-cover.amethystora-privacy-cover-opaque {
  background-color: {{ card_bg }};
  background-gradient-direction: vertical;
  background-gradient-start: {{ popover_bg }};
  background-gradient-end: {{ card_bg }};
}

.amethystora-privacy-cover .amethystora-privacy-cover-title {
  color: {{ foreground }};
}

.amethystora-privacy-cover .amethystora-privacy-cover-line {
  color: rgba({{ foreground_rgb }}, 0.8);
}

#uiGroup .amethystora-privacy-header-detail,
#uiGroup .amethystora-privacy-row-detail,
#uiGroup .amethystora-privacy-footer-note,
#uiGroup .amethystora-privacy-apps-now,
#uiGroup .amethystora-privacy-app-hosts,
#uiGroup .amethystora-privacy-apps-empty,
#uiGroup .amethystora-privacy-away-line {
  color: rgba({{ foreground_rgb }}, 0.8);
}

#uiGroup .amethystora-privacy-row-icon,
#uiGroup .amethystora-privacy-chip {
  background-color: rgba({{ foreground_rgb }}, 0.08);
  color: {{ foreground }};
}

#uiGroup .amethystora-privacy-fine {
  color: {{ success_text }};
}

#uiGroup .amethystora-privacy-look {
  color: {{ warning_text }};
}

#uiGroup .amethystora-privacy-none {
  color: {{ foreground }};
}

#uiGroup .quick-settings .amethystora-privacy-tile.amethystora-privacy-tile-fine {
  border-color: rgba({{ success_text_rgb }}, 0.45);
}

#uiGroup .quick-settings .amethystora-privacy-tile.amethystora-privacy-tile-look {
  border-color: rgba({{ warning_text_rgb }}, 0.6);
}

#uiGroup .amethystora-privacy-link {
  color: {{ accent_text }};
}

#uiGroup .amethystora-privacy-app {
  background-color: rgba({{ foreground_rgb }}, 0.06);
}

#uiGroup .amethystora-privacy-app-count {
  color: {{ accent_text }};
}

#uiGroup .amethystora-privacy-away {
  background-color: rgba({{ background_rgb }}, 0.85);
  border: 1px solid rgba({{ foreground_rgb }}, 0.16);
  color: {{ foreground }};
}
