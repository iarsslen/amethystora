/* Power you can see in the colours of {{ theme_name }} (modules/power.js): the battery's figures and shares in the
   accent's text colour and the bars from the accent to it; the busy chip in the palette's warning colour, its Quit in
   the error colour. The selectors start from the shell's top group, so these win over the module's stand-ins. */

#uiGroup .amethystora-power-battery-percent,
#uiGroup .amethystora-power-use,
#uiGroup .amethystora-power-kv { color: {{ foreground }}; }
#uiGroup .amethystora-power-battery-when,
#uiGroup .amethystora-power-head,
#uiGroup .amethystora-power-use-share,
#uiGroup .amethystora-power-kv-value { color: {{ accent_text }}; }
#uiGroup .amethystora-power-battery-how { color: rgba({{ foreground_rgb }}, 0.8); }
#uiGroup .amethystora-power-note { color: rgba({{ foreground_rgb }}, 0.65); }
#uiGroup .amethystora-power-line { background-color: rgba({{ foreground_rgb }}, 0.1); }
#uiGroup .amethystora-power-bar {
  color: {{ accent_text }};
  -amethystora-power-from: {{ accent_bg }};
  -amethystora-power-track: rgba({{ foreground_rgb }}, 0.08);
}

#uiGroup .amethystora-power-chip {
  background-color: rgba({{ warning_bg_rgb }}, 0.35);
  color: {{ foreground }};
}
#uiGroup .amethystora-power-chip-icon { color: {{ warning_text }}; }
#uiGroup .amethystora-power-busy-title { color: {{ foreground }}; }
#uiGroup .amethystora-power-busy-text { color: rgba({{ foreground_rgb }}, 0.85); }
#uiGroup .amethystora-power-busy-foot { color: rgba({{ foreground_rgb }}, 0.65); }
#uiGroup .amethystora-power-busy-button-action {
  background-color: rgba({{ foreground_rgb }}, 0.08);
  border: 1px solid rgba({{ foreground_rgb }}, 0.14);
  color: {{ foreground }};
}
#uiGroup .amethystora-power-busy-button-action:hover,
#uiGroup .amethystora-power-busy-button-action:focus { background-color: rgba({{ foreground_rgb }}, 0.14); }
#uiGroup .amethystora-power-busy-quit {
  background-color: rgba({{ error_bg_rgb }}, 0.3);
  border-color: rgba({{ error_bg_rgb }}, 0.6);
}
