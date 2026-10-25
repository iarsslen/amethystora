/* What the hairline style adds to its shape: thin lines. A control is drawn with a line that reads (3:1 on every surface,
   the theme's outline colour), a card and a popover with a quieter one, since they hold their content rather than being
   found by it. */

button:not(.flat):not(.suggested-action):not(.destructive-action):not(.circular):not(.titlebutton):not(.pill),
spinbutton,
entry,
dropdown > button,
combobox > box > button {
    box-shadow: inset 0 0 0 1px {{ outline }};
}

popover > contents,
popover.background,
popover.menu > contents {
    box-shadow: 0 0 0 1px rgba({{ foreground_rgb }}, 0.2), 0 4px 12px rgba(0, 0, 0, 0.18);
}

.card,
list.boxed-list,
list.content,
.boxed-list,
frame > border {
    box-shadow: 0 0 0 1px rgba({{ foreground_rgb }}, 0.14);
}
