/* The workspaces in the top bar, in the colours of {{ theme_name }}: the one you are on filled with the accent,
   one with windows in the text colour, an empty one fainter */

.amethystora-workspaces-label.amethystora-workspaces-active {
  background-color: {{ accent }};
  color: {{ background }};
}

.amethystora-workspaces-label.amethystora-workspaces-busy {
  color: rgba({{ foreground_rgb }}, 0.7);
}

.amethystora-workspaces-label.amethystora-workspaces-empty {
  color: rgba({{ foreground_rgb }}, 0.4);
}

/* A label being dragged, on the theme's background; the one you are on keeps its accent */
.amethystora-workspaces-dragged.amethystora-workspaces-busy,
.amethystora-workspaces-dragged.amethystora-workspaces-empty {
  background-color: {{ background }};
}

/* A window dragged from the overview over a label, the note that says where it would go, and the count of windows
   that just landed there */
.amethystora-workspaces-label.amethystora-workspaces-hit {
  background-color: rgba({{ accent_rgb }}, 0.35);
  color: {{ foreground }};
}

.amethystora-workspaces-hint.amethystora-workspaces-hint {
  color: {{ foreground }};
}

.amethystora-workspaces-badge.amethystora-workspaces-badge {
  background-color: {{ success_bg }};
  color: {{ success_fg }};
}

/* The one you are on, with a window over it: its fill and a label that reads on it (4.5:1 in every shipped theme),
   in the overview too, where the other labels' text is white */
.amethystora-workspaces-label.amethystora-workspaces-active.amethystora-workspaces-hit,
#panel:overview .amethystora-workspaces-label.amethystora-workspaces-active.amethystora-workspaces-hit {
  background-color: {{ accent_bg }};
  color: {{ accent_fg }};
}

/* Saved sets in the workspace menu: Save this workspace in the board's light outline, filled with the text colour once
   saved; the sets on a faint fill of the text colour, their apps and heading dimmed as the palette dims labels */
.amethystora-workspaces-save.amethystora-workspaces-save {
  background-color: rgba({{ foreground_rgb }}, 0.08);
  border-color: rgba({{ foreground_rgb }}, 0.14);
  color: {{ foreground }};
}

.amethystora-workspaces-save.amethystora-workspaces-save:checked {
  background-color: {{ foreground }};
  border-color: {{ foreground }};
  color: {{ background }};
}

.amethystora-workspaces-save.amethystora-workspaces-save:insensitive {
  color: rgba({{ foreground_rgb }}, {{ dim_alpha }});
}

.amethystora-workspaces-save.amethystora-workspaces-save:focus,
.amethystora-workspaces-set.amethystora-workspaces-set-focused {
  box-shadow: inset 0 0 0 2px {{ accent }};
}

.amethystora-workspaces-sets-heading.amethystora-workspaces-sets-heading,
.amethystora-workspaces-set-apps.amethystora-workspaces-set-apps {
  color: rgba({{ foreground_rgb }}, {{ dim_alpha }});
}

.amethystora-workspaces-set.amethystora-workspaces-set {
  background-color: rgba({{ foreground_rgb }}, 0.06);
  color: {{ foreground }};
}

.amethystora-workspaces-set.amethystora-workspaces-set:hover {
  background-color: rgba({{ foreground_rgb }}, 0.1);
}

.amethystora-workspaces-set-forget.amethystora-workspaces-set-forget:hover,
.amethystora-workspaces-set-forget.amethystora-workspaces-set-forget:focus {
  background-color: rgba({{ foreground_rgb }}, 0.12);
}
