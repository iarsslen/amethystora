/* Touch mode and the pen's tools in the colours of {{ theme_name }} (modules/touch.js): the handle at the right edge in
   the text colour at half strength, the hint, the ring's disc and tools and the strip in the theme's glass tint with
   the text colour, a tool the pen points at filled with the accent, and the dot at the pen's tip in the text
   colour. */

#uiGroup .amethystora-touch-handle {
  background-color: rgba({{ foreground_rgb }}, 0.5);
}

#uiGroup .amethystora-touch-hint,
#uiGroup .amethystora-touch-ring-tool,
#uiGroup .amethystora-touch-strip {
  background-color: rgba({{ background_rgb }}, 0.58);
  border-color: rgba({{ foreground_rgb }}, 0.16);
  color: {{ foreground }};
}

#uiGroup .amethystora-touch-ring-disc {
  background-color: rgba({{ background_rgb }}, 0.35);
  border-color: rgba({{ foreground_rgb }}, 0.16);
}

#uiGroup .amethystora-touch-ring-dot {
  background-color: {{ foreground }};
}

#uiGroup .amethystora-touch-ring-tool:lit,
#uiGroup .amethystora-touch-strip-tool:lit {
  background-color: {{ accent_bg }};
  color: {{ accent_fg }};
}
