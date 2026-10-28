/* The tips in the colours of {{ theme_name }}: the card and the pill a veil of the theme's background over the glass
   with a hairline of its text colour, the bulb's circle in the accent, and Got it an accent pill. Every selector starts
   from the shell's top group, one id more than the module's own stylesheet (stylesheets/hints.css), which only stands
   in until a theme has been applied. */

#uiGroup .amethystora-hints-card,
#uiGroup .amethystora-hints-pill {
  background-color: rgba({{ background_rgb }}, 0.5);
  border-color: rgba({{ foreground_rgb }}, 0.16);
  border-top-color: rgba({{ foreground_rgb }}, 0.45);
  color: {{ foreground }};
}

#uiGroup .amethystora-hints-bulb { background-color: rgba({{ accent_bg_rgb }}, 0.35); }
#uiGroup .amethystora-hints-bulb-icon { color: {{ foreground }}; }

#uiGroup .amethystora-hints-button {
  background-color: {{ accent_bg }};
  color: {{ accent_fg }};
}
#uiGroup .amethystora-hints-button:hover { background-color: rgba({{ accent_bg_rgb }}, 0.85); }
#uiGroup .amethystora-hints-button:focus { box-shadow: 0 0 0 2px {{ accent_text }}; }
