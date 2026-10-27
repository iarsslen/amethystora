/* The tiling in the colours of {{ theme_name }}: its tooltip and its hint on the theme's background with its text colour
   on them, the setting shown in the tooltip in a colour of the palette (green, cyan or yellow), the screen dimmed in
   the theme's background behind the workspace cards, and each card's frame in one of the palette's colours, muted by
   the background, in turn. Every selector starts from the shell's top group, one id more than the tiling's own
   stylesheet has for them, which only stands in until a theme has been applied. */

#uiGroup .amethystora-tiling-tooltip,
#uiGroup .amethystora-tiling-hint {
  background-color: rgba({{ background_rgb }}, 0.8);
  color: {{ foreground }};
}

#uiGroup .amethystora-tiling-tooltip .amethystora-tiling-tone-plain {
  color: {{ color2 }};
}

#uiGroup .amethystora-tiling-tooltip .amethystora-tiling-tone-centre {
  color: {{ color6 }};
}

#uiGroup .amethystora-tiling-tooltip .amethystora-tiling-tone-edge {
  color: {{ color3 }};
}

#uiGroup .amethystora-tiling-previews {
  background-color: rgba({{ background_rgb }}, 0.6);
}

#uiGroup .amethystora-tiling-card-0 {
  border-color: st-mix({{ color4 }}, {{ background }}, 70%);
}

#uiGroup .amethystora-tiling-card-1 {
  border-color: st-mix({{ color3 }}, {{ background }}, 70%);
}

#uiGroup .amethystora-tiling-card-2 {
  border-color: st-mix({{ color2 }}, {{ background }}, 70%);
}

#uiGroup .amethystora-tiling-card-3 {
  border-color: st-mix({{ color1 }}, {{ background }}, 70%);
}

#uiGroup .amethystora-tiling-card-4 {
  border-color: st-mix({{ color5 }}, {{ background }}, 70%);
}

#uiGroup .amethystora-tiling-card-5 {
  border-color: st-mix({{ color6 }}, {{ background }}, 70%);
}

#uiGroup .amethystora-tiling-card-6 {
  border-color: st-mix({{ color12 }}, {{ background }}, 70%);
}

#uiGroup .amethystora-tiling-card-7 {
  border-color: st-mix({{ color11 }}, {{ background }}, 70%);
}

#uiGroup .amethystora-tiling-card-8 {
  border-color: st-mix({{ color10 }}, {{ background }}, 70%);
}

#uiGroup .amethystora-tiling-card-9 {
  border-color: st-mix({{ color9 }}, {{ background }}, 70%);
}

#uiGroup .amethystora-tiling-card-10 {
  border-color: st-mix({{ color13 }}, {{ background }}, 70%);
}

#uiGroup .amethystora-tiling-card-11 {
  border-color: st-mix({{ color14 }}, {{ background }}, 70%);
}

#uiGroup .amethystora-tiling-card-12 {
  border-color: st-mix({{ color7 }}, {{ background }}, 70%);
}

#uiGroup .amethystora-tiling-card-13 {
  border-color: st-mix({{ color8 }}, {{ background }}, 70%);
}

#uiGroup .amethystora-tiling-tooltip .amethystora-tiling-note {
  color: rgba({{ foreground_rgb }}, 0.6);
}

#uiGroup .amethystora-tiling-screen-name,
#uiGroup .amethystora-tiling-card-name {
  background-color: rgba({{ background_rgb }}, 0.8);
  color: {{ foreground }};
}

#uiGroup .amethystora-tiling-position {
  background-color: rgba({{ foreground_rgb }}, 0.15);
}

#uiGroup .amethystora-tiling-position-mark {
  background-color: {{ accent }};
}
