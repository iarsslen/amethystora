/* Desks in the colours of {{ theme_name }} (modules/desks.js): the card and the toast's words in the text colour, what
   is said beside them at 0.8, the rows a tint of the text colour, the values in the accent's text colour, Set up filled
   with the text colour and its word in the background's, the other buttons a tint with a ring. */

#uiGroup .amethystora-desks-card,
#uiGroup .amethystora-desks-toast {
  color: {{ foreground }};
}

#uiGroup .amethystora-desks-has,
#uiGroup .amethystora-desks-note {
  color: rgba({{ foreground_rgb }}, 0.8);
}

#uiGroup .amethystora-desks-row {
  background-color: rgba({{ foreground_rgb }}, 0.06);
}

#uiGroup .amethystora-desks-value {
  color: {{ accent_text }};
}

#uiGroup .amethystora-desks-button {
  border-color: rgba({{ foreground_rgb }}, 0.14);
  background-color: rgba({{ foreground_rgb }}, 0.08);
  color: {{ foreground }};
}

#uiGroup .amethystora-desks-button:hover {
  background-color: rgba({{ foreground_rgb }}, 0.16);
}

#uiGroup .amethystora-desks-button:focus {
  box-shadow: 0 0 0 2px {{ accent_text }};
}

#uiGroup .amethystora-desks-button.amethystora-desks-primary {
  border-color: {{ foreground }};
  background-color: {{ foreground }};
  color: {{ background }};
}
