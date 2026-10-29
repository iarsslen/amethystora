/* Present mode and Scribble in the colours of {{ theme_name }}: the halo in the palette's yellow, Scribble's toolbar a
   glass pane in the theme's text colour (its popover colour where the glass is solid or not running). The ink's own
   colours never follow the theme: they have to read on any slide. */

#uiGroup .amethystora-present-halo {
  border-color: rgba({{ color3_rgb }}, 0.8);
  background-color: rgba({{ color3_rgb }}, 0.35);
}

#uiGroup .amethystora-present-toolbar {
  background-color: rgba({{ popover_bg_rgb }}, 0.94);
  border-color: rgba({{ foreground_rgb }}, 0.16);
  color: {{ foreground }};
}

#uiGroup .amethystora-present-toolbar.amethystora-glass-pane {
  background-color: transparent;
  border-color: transparent;
  -amethystora-glass-edge: rgba({{ foreground_rgb }}, 0.16);
}

#uiGroup.amethystora-glass-solid .amethystora-present-toolbar.amethystora-glass-pane {
  background-color: {{ popover_bg }};
}

#uiGroup .amethystora-present-tool,
#uiGroup .amethystora-present-clear {
  color: {{ foreground }};
}

#uiGroup .amethystora-present-tool:hover {
  background-color: rgba({{ foreground_rgb }}, 0.12);
}

#uiGroup .amethystora-present-tool:checked {
  background-color: rgba({{ foreground_rgb }}, 0.16);
}

#uiGroup .amethystora-present-separator {
  background-color: rgba({{ foreground_rgb }}, 0.2);
}
