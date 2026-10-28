/* Quick settings as live tiles in the colours of {{ theme_name }} (modules/quick.js): every tile, block and button a
   tint of the text colour over the glass, what is on in the accent, each slider filled with the accent, the dimmed
   words at the palette's dimmed strength, and what failed in its error colour. The selectors start from the shell's top
   group and name the menu twice, so that they win over the glass's own tints for these tiles; with Increase contrast
   on, the glass's outlines are kept. */

/* The tiles */

#uiGroup .quick-settings.amethystora-quick .quick-toggle,
#uiGroup .quick-settings.amethystora-quick .quick-toggle-has-menu .quick-toggle-menu-button {
  background-color: rgba({{ foreground_rgb }}, 0.07);
  border-color: transparent;
  color: {{ foreground }};
}

#uiGroup .quick-settings.amethystora-quick .quick-toggle:hover,
#uiGroup .quick-settings.amethystora-quick .quick-toggle-has-menu .quick-toggle-menu-button:hover {
  background-color: rgba({{ foreground_rgb }}, 0.12);
}

#uiGroup .quick-settings.amethystora-quick .quick-toggle:active,
#uiGroup .quick-settings.amethystora-quick .quick-toggle-has-menu .quick-toggle-menu-button:active {
  background-color: rgba({{ foreground_rgb }}, 0.16);
}

#uiGroup .quick-settings.amethystora-quick .quick-toggle .quick-toggle-subtitle {
  color: rgba({{ foreground_rgb }}, 0.85);
}

#uiGroup .quick-settings.amethystora-quick .quick-toggle:checked,
#uiGroup .quick-settings.amethystora-quick .quick-toggle-has-menu:checked .quick-toggle {
  background-color: {{ accent_bg }};
  border-color: transparent;
  color: {{ accent_fg }};
}

#uiGroup .quick-settings.amethystora-quick .quick-toggle:checked:hover {
  background-color: st-lighten({{ accent_bg }}, 6%);
}

#uiGroup .quick-settings.amethystora-quick .quick-toggle:checked .quick-toggle-subtitle {
  color: rgba({{ accent_fg_rgb }}, 0.85);
}

#uiGroup .quick-settings.amethystora-quick .quick-toggle-has-menu .quick-toggle-menu-button:checked {
  background-color: st-mix({{ accent_bg }}, {{ foreground }}, 85%);
  border-color: transparent;
  color: {{ accent_fg }};
}

#uiGroup .quick-settings.amethystora-quick .quick-toggle-has-menu .quick-toggle-separator {
  background-color: rgba({{ foreground_rgb }}, 0.12);
}

#uiGroup .quick-settings.amethystora-quick .quick-toggle-has-menu:checked .quick-toggle-separator {
  background-color: rgba({{ accent_fg_rgb }}, 0.25);
}

/* The sliders */

#uiGroup .quick-settings.amethystora-quick .quick-slider {
  background-color: rgba({{ foreground_rgb }}, 0.08);
}

#uiGroup .quick-settings.amethystora-quick .quick-slider .slider,
#uiGroup .quick-settings.amethystora-quick .amethystora-quick-app-slider {
  color: {{ accent_bg }};
  -barlevel-background-color: transparent;
  -barlevel-active-background-color: {{ accent_bg }};
}

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-app-slider {
  -barlevel-background-color: rgba({{ foreground_rgb }}, 0.08);
}

/* The theme block */

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-block {
  background-color: rgba({{ foreground_rgb }}, 0.07);
  color: {{ foreground }};
}

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-swatch {
  color: {{ foreground }};
}

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-swatch-inner {
  border-color: rgba({{ foreground_rgb }}, 0.20);
}

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-swatch:checked .amethystora-quick-swatch-inner {
  border-color: {{ foreground }};
}

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-swatch:checked .amethystora-quick-swatch-outer {
  border-color: {{ accent_bg }};
}

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-swatch:focus .amethystora-quick-swatch-outer {
  border-color: rgba({{ accent_bg_rgb }}, 0.6);
}

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-error {
  color: {{ error_text }};
}

/* Each app's own volume */

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-divider {
  background-color: rgba({{ foreground_rgb }}, 0.10);
}

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-heading,
#uiGroup .quick-settings.amethystora-quick .amethystora-quick-footer,
#uiGroup .quick-settings.amethystora-quick .amethystora-quick-hint-label,
#uiGroup .amethystora-quick-limit-text {
  color: rgba({{ foreground_rgb }}, {{ dim_alpha }});
}

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-outputs {
  background-color: rgba({{ foreground_rgb }}, 0.06);
  border-color: rgba({{ foreground_rgb }}, 0.10);
}

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-output {
  background-color: transparent;
  color: {{ foreground }};
}

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-output:hover {
  background-color: rgba({{ foreground_rgb }}, 0.10);
}

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-output:checked {
  background-color: {{ foreground }};
  color: {{ background }};
}

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-app-name {
  color: {{ foreground }};
}

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-app-mark {
  background-color: {{ accent_bg }};
  color: {{ accent_fg }};
}

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-mute {
  background-color: rgba({{ foreground_rgb }}, 0.08);
  color: {{ foreground }};
}

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-mute:hover {
  background-color: rgba({{ foreground_rgb }}, 0.14);
}

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-mute:checked {
  background-color: rgba({{ error_text_rgb }}, 0.30);
}

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-more {
  background-color: transparent;
  color: {{ accent_text }};
}

/* Screenshot, Lock, Settings and Power */

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-action {
  background-color: rgba({{ foreground_rgb }}, 0.08);
  border-color: transparent;
  color: {{ foreground }};
}

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-action:hover,
#uiGroup .quick-settings.amethystora-quick .amethystora-quick-action:focus {
  background-color: rgba({{ foreground_rgb }}, 0.14);
}

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-action:active,
#uiGroup .quick-settings.amethystora-quick .amethystora-quick-action:checked {
  background-color: rgba({{ foreground_rgb }}, 0.18);
}

/* Arranging */

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-done {
  background-color: {{ accent_bg }};
  color: {{ accent_fg }};
}

#uiGroup .quick-settings.amethystora-quick .amethystora-quick-done:hover {
  background-color: st-lighten({{ accent_bg }}, 6%);
}

#uiGroup .amethystora-quick-corner {
  background-color: rgba({{ foreground_rgb }}, 0.18);
  color: {{ foreground }};
}

#uiGroup .amethystora-quick-corner:hover {
  background-color: rgba({{ foreground_rgb }}, 0.28);
}

#uiGroup .amethystora-quick-handle:focus {
  border: 2px solid {{ accent_bg }};
}

/* The battery's charge limit */

#uiGroup .amethystora-quick-limit {
  background-color: rgba({{ foreground_rgb }}, 0.06);
}

#uiGroup .amethystora-quick-limit-title {
  color: {{ foreground }};
}

#uiGroup .amethystora-quick-error {
  color: {{ error_text }};
}

/* Increase contrast: outlines, as the glass draws GNOME's tiles then */

#uiGroup.amethystora-glass-contrast .quick-settings.amethystora-quick .quick-toggle,
#uiGroup.amethystora-glass-contrast .quick-settings.amethystora-quick .quick-toggle-has-menu .quick-toggle-menu-button,
#uiGroup.amethystora-glass-contrast .quick-settings.amethystora-quick .quick-slider,
#uiGroup.amethystora-glass-contrast .quick-settings.amethystora-quick .amethystora-quick-block,
#uiGroup.amethystora-glass-contrast .quick-settings.amethystora-quick .amethystora-quick-action,
#uiGroup.amethystora-glass-contrast .quick-settings.amethystora-quick .amethystora-quick-mute {
  background-color: transparent;
  border: 2px solid {{ foreground }};
  color: {{ foreground }};
}

#uiGroup.amethystora-glass-contrast .quick-settings.amethystora-quick .quick-toggle:checked,
#uiGroup.amethystora-glass-contrast .quick-settings.amethystora-quick .quick-toggle-has-menu:checked .quick-toggle,
#uiGroup.amethystora-glass-contrast .quick-settings.amethystora-quick .quick-toggle-has-menu .quick-toggle-menu-button:checked {
  background-color: {{ accent_bg }};
  border: 2px solid {{ accent_fg }};
  color: {{ accent_fg }};
}

#uiGroup.amethystora-glass-contrast .quick-settings.amethystora-quick .quick-toggle .quick-toggle-subtitle,
#uiGroup.amethystora-glass-contrast .quick-settings.amethystora-quick .amethystora-quick-heading,
#uiGroup.amethystora-glass-contrast .quick-settings.amethystora-quick .amethystora-quick-footer,
#uiGroup.amethystora-glass-contrast .quick-settings.amethystora-quick .amethystora-quick-hint-label {
  color: {{ foreground }};
}
