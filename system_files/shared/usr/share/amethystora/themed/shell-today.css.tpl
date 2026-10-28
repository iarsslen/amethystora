/* Today in the calendar menu, in the colours of {{ theme_name }} (modules/today.js): the dimmed headings and the
   weekday, today's cell in the accent, the task marks, the weather card and the weather
   beside the clock */

.amethystora-today .datemenu-today-button .amethystora-today-weekday,
.amethystora-today .calendar .calendar-day-heading,
.amethystora-today .calendar .calendar-day.calendar-other-month,
.amethystora-today .events-title,
.amethystora-today .event-time,
.amethystora-today .world-clocks-header,
.amethystora-today .world-clocks-timezone,
.amethystora-today .weather-header,
.amethystora-today .amethystora-today-heading,
.amethystora-today .amethystora-today-weather-icon,
.amethystora-today .amethystora-today-weather-rest {
  color: rgba({{ foreground_rgb }}, {{ dim_alpha }});
}

.amethystora-today .calendar .calendar-day.calendar-today,
.amethystora-today .calendar .calendar-day.calendar-today:hover {
  background-color: {{ accent_bg }};
  color: {{ accent_fg }} !important;
}

/* The date heading reads as a heading, although GNOME draws the Today button as insensitive on today */
.amethystora-today .datemenu-today-button .amethystora-today-date {
  color: {{ foreground }};
}

.amethystora-today .event-time {
  color: {{ accent_text }};
}

.amethystora-today .amethystora-today-tasks:hover,
.amethystora-today .amethystora-today-tasks:focus {
  background-color: rgba({{ foreground_rgb }}, 0.07);
}

.amethystora-today .amethystora-today-mark {
  border-color: rgba({{ foreground_rgb }}, 0.55);
}

.amethystora-today .amethystora-today-title,
.amethystora-today .amethystora-today-weather-first {
  color: {{ foreground }};
}

.amethystora-today .amethystora-today-more {
  color: {{ accent_text }};
}

.amethystora-today .amethystora-today-weather-off {
  border-color: rgba({{ foreground_rgb }}, 0.28);
}

.amethystora-today .amethystora-today-weather-button {
  background-color: rgba({{ foreground_rgb }}, 0.12);
  color: {{ foreground }};
}

.amethystora-today .amethystora-today-weather-button.amethystora-today-weather-accent {
  background-color: {{ accent_bg }};
  color: {{ accent_fg }};
}

#panel .amethystora-today-weather-pill.amethystora-today-weather-pill {
  background-color: rgba({{ foreground_rgb }}, 0.10);
}
