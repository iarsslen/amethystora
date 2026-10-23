/* The meters in the top bar and their menus, in the colours of {{ theme_name }}: the bars and charts in the accent,
   their troughs and the quieter text in the text colour, which is light on a dark theme and dark on a light one */

#panel .amethystora-meters-trough {
  background-color: rgba({{ foreground_rgb }}, 0.2);
}

#panel .amethystora-meters-bar {
  background-color: {{ accent }};
}

.amethystora-meters-menu .amethystora-meters-heading {
  color: rgba({{ foreground_rgb }}, 0.7);
}

.amethystora-meters-menu .amethystora-meters-capacity {
  -barlevel-background-color: rgba({{ foreground_rgb }}, 0.12);
  -barlevel-active-background-color: {{ accent }};
}

.amethystora-meters-menu .amethystora-meters-plot {
  background-color: rgba({{ foreground_rgb }}, 0.08);
}

.amethystora-meters-menu .amethystora-meters-chart {
  color: {{ accent }};
}

.amethystora-meters-menu .amethystora-meters-mark {
  color: rgba({{ foreground_rgb }}, 0.6);
}

.amethystora-meters-popup.amethystora-meters-tip {
  background-color: {{ background }};
  color: {{ foreground }};
}
