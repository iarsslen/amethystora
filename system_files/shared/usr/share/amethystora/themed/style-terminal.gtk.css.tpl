/* What the terminal style adds to its shape: everything square, every control and card lined, and the control that has
   the keyboard lined in the accent. 20-gtk-apps.sh puts this file in both user stylesheets, after the window buttons,
   whose lights stay round, their own rules being more particular than a star. */

* {
    border-radius: 0;
}

/* What is round by what it is stays round: a radio button, a face */
radio,
avatar {
    border-radius: 100%;
}

button:not(.flat):not(.suggested-action):not(.destructive-action):not(.circular):not(.titlebutton):not(.pill),
spinbutton,
entry,
dropdown > button,
combobox > box > button {
    box-shadow: inset 0 0 0 1px {{ outline }};
}

popover > contents,
popover.background,
popover.menu > contents,
.card,
list.boxed-list,
list.content,
.boxed-list,
frame > border {
    box-shadow: 0 0 0 1px rgba({{ foreground_rgb }}, 0.3);
}

entry:focus-within,
spinbutton:focus-within {
    box-shadow: inset 0 0 0 1px {{ accent_text }};
}

window.csd:not(.maximized):not(.fullscreen):not(.tiled),
window.csd:not(.maximized):not(.fullscreen):not(.tiled) > decoration {
    box-shadow: 0 0 0 1px rgba({{ foreground_rgb }}, 0.35), 0 6px 18px rgba(0, 0, 0, 0.3);
}
