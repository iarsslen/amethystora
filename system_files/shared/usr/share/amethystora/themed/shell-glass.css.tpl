/* The glass in the colours of {{ theme_name }}: every surface's veil in the theme's background (the glass draws it,
   faint in the dark scheme, milky in the light one, thicker where a bright wallpaper asks for it), its text and the
   washes of the controls on it in the theme's text colour, which is light on a dark theme and dark on a light one,
   the reds of an on-screen display's overdrive and of a recording in the palette's, and GNOME's accent colour for what
   is on. Every selector starts from the shell's top group, one id more than the glass's own stylesheet has for the
   surfaces, which only stands in until a theme has been applied. */

/* The surfaces, with their corners. The glass draws their veil and hairline, St neither. */

#uiGroup .amethystora-glass-surface,
#uiGroup .amethystora-glass-surface:hover,
#uiGroup .amethystora-glass-surface:active,
#uiGroup .amethystora-glass-surface:focus {
  background-color: transparent;
  border-color: transparent;
  color: {{ foreground }};
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light,
#uiGroup .amethystora-glass-surface.amethystora-glass-light:hover,
#uiGroup .amethystora-glass-surface.amethystora-glass-light:active,
#uiGroup .amethystora-glass-surface.amethystora-glass-light:focus {
  background-color: transparent;
  border-color: transparent;
  color: {{ foreground }};
}

#uiGroup #keyboard.amethystora-glass-surface,
#uiGroup #keyboard.amethystora-glass-surface.amethystora-glass-light {
  background-color: transparent;
}

/* What the glass draws a surface's veil from, and the accent its light gathers in */

#uiGroup .amethystora-glass-pane {
  -amethystora-glass-ground: {{ background }};
  -amethystora-glass-accent: {{ accent }};
}

/* Going solid, the theme's surfaces fade in over the glass, which stays under them until they are in
   (modules/glass.js); the glass and every other change of a surface come at once */

#uiGroup.amethystora-glass-solid .amethystora-glass-pane {
  transition-duration: 300ms;
}

/* Solid (Reduce transparency, High Contrast, the power saver): the theme's own surfaces, plain, with the shadow the
   glass gave them; St draws them, with circular corners */

#uiGroup.amethystora-glass-solid .amethystora-glass-surface,
#uiGroup.amethystora-glass-solid .amethystora-glass-surface:hover,
#uiGroup.amethystora-glass-solid .amethystora-glass-surface:active,
#uiGroup.amethystora-glass-solid .amethystora-glass-surface:focus {
  background-color: {{ popover_bg }};
  border-color: rgba({{ foreground_rgb }}, 0.08);
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.16);
}

#uiGroup.amethystora-glass-solid .amethystora-glass-surface.amethystora-glass-light,
#uiGroup.amethystora-glass-solid .amethystora-glass-surface.amethystora-glass-light:hover,
#uiGroup.amethystora-glass-solid .amethystora-glass-surface.amethystora-glass-light:active,
#uiGroup.amethystora-glass-solid .amethystora-glass-surface.amethystora-glass-light:focus {
  box-shadow: 0 8px 22px rgba(0, 0, 0, 0.08);
}

#uiGroup.amethystora-glass-solid .amethystora-glass-surface.amethystora-glass-dialog,
#uiGroup.amethystora-glass-solid .amethystora-glass-surface.amethystora-glass-dialog:hover,
#uiGroup.amethystora-glass-solid .amethystora-glass-surface.amethystora-glass-dialog:active,
#uiGroup.amethystora-glass-solid .amethystora-glass-surface.amethystora-glass-dialog:focus {
  background-color: {{ dialog_bg }};
}

#uiGroup.amethystora-glass-solid .amethystora-glass-surface.amethystora-glass-inner,
#uiGroup.amethystora-glass-solid #keyboard.amethystora-glass-surface {
  box-shadow: none;
}

#uiGroup.amethystora-glass-solid #keyboard.amethystora-glass-surface,
#uiGroup.amethystora-glass-solid #keyboard.amethystora-glass-surface.amethystora-glass-light {
  background-color: {{ popover_bg }};
}

#uiGroup.amethystora-glass-solid #panel .panel-button.amethystora-glass-pill,
#uiGroup.amethystora-glass-solid #dash.amethystora-dock-dash .dash-background {
  background-color: {{ popover_bg }};
  border-color: rgba({{ foreground_rgb }}, 0.08);
}

/* Increase contrast (GNOME's High Contrast, whose own stylesheet is underneath): solid as above, every surface
   outlined in the text colour, dimmed text shown plain and the controls outlined */

#uiGroup.amethystora-glass-contrast .amethystora-glass-surface,
#uiGroup.amethystora-glass-contrast .amethystora-glass-surface:hover,
#uiGroup.amethystora-glass-contrast .amethystora-glass-surface:active,
#uiGroup.amethystora-glass-contrast .amethystora-glass-surface:focus,
#uiGroup.amethystora-glass-contrast #keyboard.amethystora-glass-surface,
#uiGroup.amethystora-glass-contrast #panel .panel-button.amethystora-glass-pill,
#uiGroup.amethystora-glass-contrast #dash.amethystora-dock-dash .dash-background {
  border: 2px solid {{ foreground }};
  color: {{ foreground }};
}

#uiGroup.amethystora-glass-contrast .amethystora-glass-surface .popup-menu-item:insensitive,
#uiGroup.amethystora-glass-contrast .amethystora-glass-surface .button:insensitive,
#uiGroup.amethystora-glass-contrast .amethystora-glass-surface .icon-button:insensitive,
#uiGroup.amethystora-glass-contrast .amethystora-glass-surface .modal-dialog-button-box .modal-dialog-button:insensitive,
#uiGroup.amethystora-glass-contrast .amethystora-glass-surface .message .message-header,
#uiGroup.amethystora-glass-contrast .amethystora-glass-surface .message-notification-group .message-group-header,
#uiGroup.amethystora-glass-contrast .amethystora-glass-banner .message-header,
#uiGroup.amethystora-glass-contrast .amethystora-glass-surface .calendar .calendar-month-header .calendar-month-label,
#uiGroup.amethystora-glass-contrast .amethystora-glass-surface .calendar .calendar-day-heading,
#uiGroup.amethystora-glass-contrast .amethystora-glass-surface .calendar .calendar-day.calendar-other-month,
#uiGroup.amethystora-glass-contrast .amethystora-glass-surface .calendar .calendar-day.calendar-other-month.calendar-weekend,
#uiGroup.amethystora-glass-contrast .amethystora-glass-surface .events-section-title,
#uiGroup.amethystora-glass-contrast .amethystora-glass-surface .event-time,
#uiGroup.amethystora-glass-contrast .amethystora-glass-surface .world-clocks-header,
#uiGroup.amethystora-glass-contrast .amethystora-glass-surface .weather-header,
#uiGroup.amethystora-glass-contrast .amethystora-glass-surface .message-secondary-bin {
  color: {{ foreground }};
}

#uiGroup.amethystora-glass-contrast .amethystora-glass-surface .quick-toggle,
#uiGroup.amethystora-glass-contrast .amethystora-glass-surface .quick-toggle-has-menu .quick-toggle-menu-button,
#uiGroup.amethystora-glass-contrast .amethystora-glass-surface .quick-toggle:hover,
#uiGroup.amethystora-glass-contrast .amethystora-glass-surface .quick-toggle-has-menu .quick-toggle-menu-button:hover {
  background-color: transparent;
  border: 2px solid {{ foreground }};
  color: {{ foreground }};
}

#uiGroup.amethystora-glass-contrast .amethystora-glass-surface .quick-toggle:checked,
#uiGroup.amethystora-glass-contrast .amethystora-glass-surface .quick-toggle:checked:hover,
#uiGroup.amethystora-glass-contrast .amethystora-glass-surface .quick-toggle-has-menu:checked .quick-toggle,
#uiGroup.amethystora-glass-contrast .amethystora-glass-surface .quick-toggle-has-menu .quick-toggle-menu-button:checked {
  background-color: {{ accent_bg }};
  border: 2px solid {{ accent_fg }};
  color: {{ accent_fg }};
}

#uiGroup.amethystora-glass-contrast .amethystora-glass-surface .quick-slider {
  background-color: transparent;
  border: 2px solid {{ foreground }};
}

/* Menu items */

#uiGroup .amethystora-glass-surface .popup-menu-item:hover,
#uiGroup .amethystora-glass-surface .popup-menu-item:focus,
#uiGroup .amethystora-glass-surface .popup-menu-item:selected {
  background-color: rgba({{ foreground_rgb }}, 0.10);
  color: {{ foreground }};
}

#uiGroup .amethystora-glass-surface .popup-menu-item:active,
#uiGroup .amethystora-glass-surface .popup-menu-item:checked,
#uiGroup .amethystora-glass-surface .popup-menu-item:active:hover,
#uiGroup .amethystora-glass-surface .popup-menu-item:checked:hover {
  background-color: rgba({{ foreground_rgb }}, 0.14);
  color: {{ foreground }};
}

#uiGroup .amethystora-glass-surface .popup-sub-menu {
  background-color: rgba({{ background_rgb }}, 0.36);
  border-color: transparent;
}

#uiGroup .amethystora-glass-surface .popup-sub-menu .popup-menu-item:hover,
#uiGroup .amethystora-glass-surface .popup-sub-menu .popup-menu-item:focus {
  background-color: rgba({{ foreground_rgb }}, 0.10);
}

#uiGroup .amethystora-glass-light .popup-menu-item,
#uiGroup .amethystora-glass-light .popup-inactive-menu-item {
  color: {{ foreground }};
}

#uiGroup .amethystora-glass-light .popup-menu-item:insensitive {
  color: rgba({{ foreground_rgb }}, 0.5);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .popup-menu-item:hover,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .popup-menu-item:focus,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .popup-menu-item:selected,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .popup-sub-menu .popup-menu-item:hover,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .popup-sub-menu .popup-menu-item:focus {
  background-color: rgba({{ foreground_rgb }}, 0.06);
  color: {{ foreground }};
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .popup-menu-item:active,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .popup-menu-item:checked,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .popup-menu-item:active:hover,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .popup-menu-item:checked:hover {
  background-color: rgba({{ foreground_rgb }}, 0.10);
  color: {{ foreground }};
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .popup-sub-menu {
  background-color: rgba({{ background_rgb }}, 0.58);
}

/* Buttons: translucent at rest, a step up when pointed at and another when pressed */

#uiGroup .amethystora-glass-surface .button,
#uiGroup .amethystora-glass-surface .icon-button,
#uiGroup .amethystora-glass-surface .calendar .calendar-month-header .pager-button,
#uiGroup .amethystora-glass-surface .screenshot-ui-show-pointer-button {
  background-color: rgba({{ foreground_rgb }}, 0.08);
  color: {{ foreground }};
}

#uiGroup .amethystora-glass-surface .button:hover,
#uiGroup .amethystora-glass-surface .icon-button:hover,
#uiGroup .amethystora-glass-surface .calendar .calendar-month-header .pager-button:hover,
#uiGroup .amethystora-glass-surface .screenshot-ui-show-pointer-button:hover,
#uiGroup .amethystora-glass-surface .button:focus,
#uiGroup .amethystora-glass-surface .icon-button:focus {
  background-color: rgba({{ foreground_rgb }}, 0.13);
}

#uiGroup .amethystora-glass-surface .button:active,
#uiGroup .amethystora-glass-surface .icon-button:active,
#uiGroup .amethystora-glass-surface .calendar .calendar-month-header .pager-button:active,
#uiGroup .amethystora-glass-surface .screenshot-ui-show-pointer-button:active,
#uiGroup .amethystora-glass-surface .screenshot-ui-show-pointer-button:checked,
#uiGroup .amethystora-glass-surface .button:checked,
#uiGroup .amethystora-glass-surface .icon-button:checked {
  background-color: rgba({{ foreground_rgb }}, 0.18);
}

#uiGroup .amethystora-glass-surface .button:insensitive,
#uiGroup .amethystora-glass-surface .icon-button:insensitive {
  background-color: rgba({{ foreground_rgb }}, 0.05);
  color: rgba({{ foreground_rgb }}, 0.5);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .button,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .icon-button,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .calendar .calendar-month-header .pager-button,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .screenshot-ui-show-pointer-button {
  background-color: rgba({{ foreground_rgb }}, 0.08);
  color: {{ foreground }};
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .button:hover,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .icon-button:hover,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .calendar .calendar-month-header .pager-button:hover,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .screenshot-ui-show-pointer-button:hover,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .button:focus,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .icon-button:focus {
  background-color: rgba({{ foreground_rgb }}, 0.12);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .button:active,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .icon-button:active,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .calendar .calendar-month-header .pager-button:active,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .screenshot-ui-show-pointer-button:active,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .screenshot-ui-show-pointer-button:checked,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .button:checked,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .icon-button:checked {
  background-color: rgba({{ foreground_rgb }}, 0.16);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .button:insensitive,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .icon-button:insensitive {
  background-color: rgba({{ foreground_rgb }}, 0.04);
  color: rgba({{ foreground_rgb }}, 0.5);
}

/* What is on keeps GNOME's accent colour */

#uiGroup .amethystora-glass-surface .button.default,
#uiGroup .amethystora-glass-surface .icon-button.default,
#uiGroup .amethystora-glass-surface .quick-toggle:checked,
#uiGroup .amethystora-glass-surface .quick-toggle-has-menu:checked .quick-toggle,
#uiGroup .amethystora-glass-surface .calendar .calendar-day.calendar-today,
#uiGroup .amethystora-glass-surface .calendar .calendar-day:selected,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .button.default,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .icon-button.default,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .quick-toggle:checked,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .calendar .calendar-day.calendar-today,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .calendar .calendar-day:selected {
  background-color: {{ accent_bg }};
  color: {{ accent_fg }};
  border-color: transparent;
}

#uiGroup .amethystora-glass-surface .button.default:hover,
#uiGroup .amethystora-glass-surface .quick-toggle:checked:hover {
  background-color: st-lighten({{ accent_bg }}, 6%);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .button.default:hover,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .quick-toggle:checked:hover {
  background-color: st-darken({{ accent_bg }}, 6%);
}

/* The quick settings' toggles */

#uiGroup .amethystora-glass-surface .quick-toggle,
#uiGroup .amethystora-glass-surface .quick-toggle-has-menu .quick-toggle-menu-button {
  background-color: rgba({{ foreground_rgb }}, 0.11);
  border-color: rgba({{ foreground_rgb }}, 0.08);
}

#uiGroup .amethystora-glass-surface .quick-toggle:hover,
#uiGroup .amethystora-glass-surface .quick-toggle-has-menu .quick-toggle-menu-button:hover {
  background-color: rgba({{ foreground_rgb }}, 0.18);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .quick-toggle,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .quick-toggle-has-menu .quick-toggle-menu-button {
  background-color: rgba({{ background_rgb }}, 0.62);
  border-color: rgba({{ foreground_rgb }}, 0.08);
  color: {{ foreground }};
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .quick-toggle:hover,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .quick-toggle-has-menu .quick-toggle-menu-button:hover {
  background-color: rgba({{ background_rgb }}, 0.78);
}

#uiGroup .amethystora-glass-surface .quick-toggle:checked,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .quick-toggle:checked {
  border-color: transparent;
}

#uiGroup .amethystora-glass-surface .quick-toggle-has-menu .quick-toggle-menu-button:checked {
  background-color: st-mix({{ accent_bg }}, {{ foreground }}, 85%);
  color: {{ accent_fg }};
  border-color: transparent;
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .quick-toggle-has-menu .quick-toggle-menu-button:checked {
  background-color: st-mix({{ accent_bg }}, {{ background }}, 85%);
  color: {{ accent_fg }};
  border-color: transparent;
}

/* The sliders' rows are clear; their buttons only show when pointed at */

#uiGroup .amethystora-glass-surface .quick-slider .icon-button {
  background-color: transparent;
}

#uiGroup .amethystora-glass-surface .quick-slider .icon-button:hover {
  background-color: rgba({{ foreground_rgb }}, 0.12);
}

#uiGroup .amethystora-glass-surface .quick-slider .icon-button:active {
  background-color: rgba({{ foreground_rgb }}, 0.18);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .quick-slider .icon-button {
  background-color: transparent;
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .quick-slider .icon-button:hover {
  background-color: rgba({{ foreground_rgb }}, 0.08);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .quick-slider .icon-button:active {
  background-color: rgba({{ foreground_rgb }}, 0.12);
}

/* The calendar */

#uiGroup .amethystora-glass-surface .calendar,
#uiGroup .amethystora-glass-surface .calendar .calendar-day,
#uiGroup .amethystora-glass-surface .calendar .calendar-day-heading,
#uiGroup .amethystora-glass-surface .calendar .calendar-month-header .calendar-month-label {
  background-color: transparent;
  color: {{ foreground }};
}

#uiGroup .amethystora-glass-surface .calendar .calendar-day:hover,
#uiGroup .amethystora-glass-surface .calendar .calendar-day:focus {
  background-color: rgba({{ foreground_rgb }}, 0.10);
}

#uiGroup .amethystora-glass-surface .calendar .calendar-day-heading,
#uiGroup .amethystora-glass-surface .calendar .calendar-day.calendar-weekend {
  color: rgba({{ foreground_rgb }}, 0.7);
}

#uiGroup .amethystora-glass-surface .calendar .calendar-day.calendar-other-month,
#uiGroup .amethystora-glass-surface .calendar .calendar-day.calendar-other-month.calendar-weekend {
  color: rgba({{ foreground_rgb }}, 0.5);
}

#uiGroup .amethystora-glass-surface .datemenu-today-button,
#uiGroup .amethystora-glass-surface .calendar:hover {
  background-color: transparent;
}

#uiGroup .amethystora-glass-surface .datemenu-today-button:hover {
  background-color: rgba({{ foreground_rgb }}, 0.08);
}

#uiGroup .amethystora-glass-surface .events-button,
#uiGroup .amethystora-glass-surface .world-clocks-button,
#uiGroup .amethystora-glass-surface .weather-button {
  background-color: rgba({{ foreground_rgb }}, 0.07);
}

#uiGroup .amethystora-glass-surface .events-button:hover,
#uiGroup .amethystora-glass-surface .world-clocks-button:hover,
#uiGroup .amethystora-glass-surface .weather-button:hover {
  background-color: rgba({{ foreground_rgb }}, 0.12);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .calendar,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .calendar .calendar-day,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .calendar .calendar-day-heading,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .calendar .calendar-month-header .calendar-month-label {
  color: {{ foreground }};
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .calendar .calendar-day:hover,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .calendar .calendar-day:focus {
  background-color: rgba({{ foreground_rgb }}, 0.08);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .calendar .calendar-day-heading,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .calendar .calendar-day.calendar-weekend {
  color: rgba({{ foreground_rgb }}, 0.7);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .calendar .calendar-day.calendar-other-month,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .calendar .calendar-day.calendar-other-month.calendar-weekend {
  color: rgba({{ foreground_rgb }}, 0.42);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .datemenu-today-button:hover {
  background-color: rgba({{ foreground_rgb }}, 0.06);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .events-button,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .world-clocks-button,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .weather-button {
  background-color: rgba({{ background_rgb }}, 0.28);
  color: {{ foreground }};
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .events-button:hover,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .world-clocks-button:hover,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .weather-button:hover {
  background-color: rgba({{ background_rgb }}, 0.40);
}

/* Notifications in the drawer: cards stacked under another are paler still */

#uiGroup .amethystora-glass-surface .message {
  background-color: rgba({{ foreground_rgb }}, 0.07);
  border-color: transparent;
}

#uiGroup .amethystora-glass-surface .message:hover {
  background-color: rgba({{ foreground_rgb }}, 0.12);
}

#uiGroup .amethystora-glass-surface .message:focus,
#uiGroup .amethystora-glass-surface .message:active {
  background-color: rgba({{ foreground_rgb }}, 0.15);
}

#uiGroup .amethystora-glass-surface .message:second-in-stack {
  background-color: rgba({{ foreground_rgb }}, 0.05);
}

#uiGroup .amethystora-glass-surface .message:lower-in-stack {
  background-color: rgba({{ foreground_rgb }}, 0.02);
}

#uiGroup .amethystora-glass-surface .message .message-header,
#uiGroup .amethystora-glass-surface .message-notification-group .message-group-header {
  color: rgba({{ foreground_rgb }}, 0.7);
}

#uiGroup .amethystora-glass-surface .message-list {
  border-color: rgba({{ foreground_rgb }}, 0.1);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .message {
  background-color: rgba({{ background_rgb }}, 0.58);
  color: {{ foreground }};
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .message:hover {
  background-color: rgba({{ background_rgb }}, 0.40);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .message:focus,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .message:active {
  background-color: rgba({{ background_rgb }}, 0.70);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .message:second-in-stack {
  background-color: rgba({{ background_rgb }}, 0.54);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .message:lower-in-stack {
  background-color: rgba({{ background_rgb }}, 0.44);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .message .message-header,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .message-notification-group .message-group-header {
  color: rgba({{ foreground_rgb }}, 0.7);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .message-list {
  border-color: rgba({{ foreground_rgb }}, 0.1);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .notification-button,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .message .message-header .message-close-button,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .message .message-header .message-expand-button,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .message-notification-group .message-collapse-button,
#uiGroup .amethystora-glass-light.amethystora-glass-banner .notification-button,
#uiGroup .amethystora-glass-light.amethystora-glass-banner .message-header .message-close-button {
  background-color: rgba({{ foreground_rgb }}, 0.08);
  color: {{ foreground }};
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .notification-button:hover,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .message .message-header .message-close-button:hover,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .message .message-header .message-expand-button:hover,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .message-notification-group .message-collapse-button:hover,
#uiGroup .amethystora-glass-light.amethystora-glass-banner .notification-button:hover,
#uiGroup .amethystora-glass-light.amethystora-glass-banner .message-header .message-close-button:hover {
  background-color: rgba({{ foreground_rgb }}, 0.12);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .notification-button:active,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .message .message-header .message-close-button:active,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .message .message-header .message-expand-button:active,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .message-notification-group .message-collapse-button:active,
#uiGroup .amethystora-glass-light.amethystora-glass-banner .notification-button:active,
#uiGroup .amethystora-glass-light.amethystora-glass-banner .message-header .message-close-button:active {
  background-color: rgba({{ foreground_rgb }}, 0.16);
}

#uiGroup .amethystora-glass-light.amethystora-glass-banner .message-header {
  color: rgba({{ foreground_rgb }}, 0.7);
}

/* Text entries */

#uiGroup .amethystora-glass-surface StEntry {
  background-color: rgba({{ foreground_rgb }}, 0.08);
  color: rgba({{ foreground_rgb }}, 0.7);
}

#uiGroup .amethystora-glass-surface StEntry:hover {
  background-color: rgba({{ foreground_rgb }}, 0.10);
}

#uiGroup .amethystora-glass-surface StEntry:focus {
  background-color: rgba({{ foreground_rgb }}, 0.13);
  color: {{ foreground }};
}

#uiGroup .amethystora-glass-surface StEntry StLabel.hint-text {
  color: rgba({{ foreground_rgb }}, 0.5);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light StEntry {
  background-color: rgba({{ background_rgb }}, 0.42);
  color: {{ foreground }};
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light StEntry:focus {
  background-color: rgba({{ background_rgb }}, 0.54);
  color: {{ foreground }};
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light StEntry StLabel.hint-text {
  color: rgba({{ foreground_rgb }}, 0.5);
}

/* Scroll bars: no trough, and a handle that shows on glass */

#uiGroup .amethystora-glass-surface StScrollBar > .vhandle,
#uiGroup .amethystora-glass-surface StScrollBar > .hhandle {
  background-color: rgba({{ foreground_rgb }}, 0.28);
}

#uiGroup .amethystora-glass-surface StScrollBar > .vhandle:hover,
#uiGroup .amethystora-glass-surface StScrollBar > .hhandle:hover {
  background-color: rgba({{ foreground_rgb }}, 0.38);
}

#uiGroup .amethystora-glass-surface StScrollBar > .vhandle:active,
#uiGroup .amethystora-glass-surface StScrollBar > .hhandle:active {
  background-color: rgba({{ foreground_rgb }}, 0.46);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light StScrollBar > .vhandle,
#uiGroup .amethystora-glass-surface.amethystora-glass-light StScrollBar > .hhandle {
  background-color: rgba({{ foreground_rgb }}, 0.24);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light StScrollBar > .vhandle:hover,
#uiGroup .amethystora-glass-surface.amethystora-glass-light StScrollBar > .hhandle:hover {
  background-color: rgba({{ foreground_rgb }}, 0.34);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light StScrollBar > .vhandle:active,
#uiGroup .amethystora-glass-surface.amethystora-glass-light StScrollBar > .hhandle:active {
  background-color: rgba({{ foreground_rgb }}, 0.42);
}

/* The level in an on-screen display */

#uiGroup .amethystora-glass-osd .level {
  -barlevel-background-color: rgba({{ foreground_rgb }}, 0.14);
  -barlevel-active-background-color: {{ foreground }};
  -barlevel-overdrive-color: {{ color9 }};
}

#uiGroup .amethystora-glass-osd.amethystora-glass-light .level {
  -barlevel-background-color: rgba({{ foreground_rgb }}, 0.12);
  -barlevel-active-background-color: {{ foreground }};
  -barlevel-overdrive-color: {{ color1 }};
}

/* The window switcher */

#uiGroup .amethystora-glass-surface .item-box:hover {
  background-color: rgba({{ foreground_rgb }}, 0.20);
}

#uiGroup .amethystora-glass-surface .item-box:selected {
  background-color: rgba({{ foreground_rgb }}, 0.13);
}

#uiGroup .amethystora-glass-surface .item-box:active {
  background-color: rgba({{ foreground_rgb }}, 0.24);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .item-box {
  color: {{ foreground }};
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .item-box:hover {
  background-color: rgba({{ foreground_rgb }}, 0.20);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .item-box:selected {
  background-color: rgba({{ foreground_rgb }}, 0.12);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .item-box:active {
  background-color: rgba({{ foreground_rgb }}, 0.24);
}

/* Dialogs' buttons. These selectors have no id and one class fewer than the others, so that a rule of another
   module for a button of its own (the Uninstall question's red one, stylesheets/bazaar.css) stays above them
   whichever stylesheet was loaded last; they still outrank GNOME's own, which they follow in the order of loading. */

.amethystora-glass-surface .modal-dialog-button-box .modal-dialog-button,
.amethystora-glass-surface .modal-dialog-button-box .modal-dialog-button:focus {
  background-color: rgba({{ foreground_rgb }}, 0.08);
}

.amethystora-glass-surface .modal-dialog-button-box .modal-dialog-button:hover {
  background-color: rgba({{ foreground_rgb }}, 0.13);
}

.amethystora-glass-surface .modal-dialog-button-box .modal-dialog-button:active {
  background-color: rgba({{ foreground_rgb }}, 0.18);
}

.amethystora-glass-surface .modal-dialog-button-box .modal-dialog-button:insensitive {
  background-color: rgba({{ foreground_rgb }}, 0.08);
  color: rgba({{ foreground_rgb }}, 0.5);
}

.amethystora-glass-light .modal-dialog-button-box .modal-dialog-button,
.amethystora-glass-light .modal-dialog-button-box .modal-dialog-button:focus {
  background-color: rgba({{ background_rgb }}, 0.42);
  color: {{ foreground }};
}

.amethystora-glass-light .modal-dialog-button-box .modal-dialog-button:hover {
  background-color: rgba({{ background_rgb }}, 0.54);
}

.amethystora-glass-light .modal-dialog-button-box .modal-dialog-button:active {
  background-color: rgba({{ foreground_rgb }}, 0.10);
}

.amethystora-glass-light .modal-dialog-button-box .modal-dialog-button:insensitive {
  color: rgba({{ foreground_rgb }}, 0.5);
}

/* The screenshot UI's panel */

#uiGroup .amethystora-glass-surface .screenshot-ui-type-button {
  background-color: transparent;
}

#uiGroup .amethystora-glass-surface .screenshot-ui-type-button:checked,
#uiGroup .amethystora-glass-surface .screenshot-ui-type-button:focus {
  background-color: rgba({{ foreground_rgb }}, 0.13);
}

#uiGroup .amethystora-glass-surface .screenshot-ui-type-button:hover {
  background-color: rgba({{ foreground_rgb }}, 0.20);
}

#uiGroup .amethystora-glass-surface .screenshot-ui-type-button:active {
  background-color: rgba({{ foreground_rgb }}, 0.18);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .screenshot-ui-type-button {
  color: {{ foreground }};
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .screenshot-ui-type-button:checked,
#uiGroup .amethystora-glass-surface.amethystora-glass-light .screenshot-ui-type-button:focus {
  background-color: rgba({{ foreground_rgb }}, 0.13);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .screenshot-ui-type-button:hover {
  background-color: rgba({{ foreground_rgb }}, 0.20);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .screenshot-ui-type-button:active {
  background-color: rgba({{ foreground_rgb }}, 0.18);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .screenshot-ui-capture-button {
  border-color: {{ foreground }};
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .screenshot-ui-capture-button .screenshot-ui-capture-button-circle {
  background-color: {{ foreground }};
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .screenshot-ui-capture-button:cast .screenshot-ui-capture-button-circle {
  background-color: {{ color1 }};
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .screenshot-ui-shot-cast-container {
  background-color: rgba({{ foreground_rgb }}, 0.10);
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .screenshot-ui-shot-cast-button {
  color: {{ foreground }};
}

#uiGroup .amethystora-glass-surface.amethystora-glass-light .screenshot-ui-shot-cast-button:checked {
  background-color: {{ foreground }};
  color: {{ background }};
}

/* The on-screen keyboard's keys */

#uiGroup #keyboard.amethystora-glass-surface .keyboard-key {
  background-color: rgba({{ foreground_rgb }}, 0.08);
  box-shadow: inset 0 -1px 0 0 rgba({{ background_rgb }}, 0.18);
  color: {{ foreground }};
}

#uiGroup #keyboard.amethystora-glass-surface .keyboard-key:hover {
  background-color: rgba({{ foreground_rgb }}, 0.20);
}

#uiGroup #keyboard.amethystora-glass-surface .keyboard-key:active {
  background-color: rgba({{ foreground_rgb }}, 0.18);
}

#uiGroup #keyboard.amethystora-glass-surface .keyboard-key:checked {
  background-color: rgba({{ foreground_rgb }}, 0.13);
  box-shadow: inset 0 0 0 2px {{ accent_bg }};
}

#uiGroup #keyboard.amethystora-glass-surface .keyboard-key.default-key {
  background-color: rgba({{ foreground_rgb }}, 0.05);
}

#uiGroup #keyboard.amethystora-glass-surface .keyboard-key:latched,
#uiGroup #keyboard.amethystora-glass-surface .keyboard-key.default-key:latched {
  background-color: {{ accent_bg }};
  color: {{ accent_fg }};
}

#uiGroup #keyboard.amethystora-glass-surface.amethystora-glass-light .keyboard-key {
  background-color: rgba({{ foreground_rgb }}, 0.08);
  box-shadow: inset 0 -1px 0 0 rgba({{ foreground_rgb }}, 0.12);
  color: {{ foreground }};
}

#uiGroup #keyboard.amethystora-glass-surface.amethystora-glass-light .keyboard-key:hover {
  background-color: rgba({{ foreground_rgb }}, 0.14);
}

#uiGroup #keyboard.amethystora-glass-surface.amethystora-glass-light .keyboard-key:active {
  background-color: rgba({{ foreground_rgb }}, 0.12);
}

#uiGroup #keyboard.amethystora-glass-surface.amethystora-glass-light .keyboard-key.default-key {
  background-color: rgba({{ foreground_rgb }}, 0.05);
}

#uiGroup #keyboard.amethystora-glass-surface.amethystora-glass-light .keyboard-key:latched,
#uiGroup #keyboard.amethystora-glass-surface.amethystora-glass-light .keyboard-key.default-key:latched {
  background-color: {{ accent_bg }};
  color: {{ accent_fg }};
}
