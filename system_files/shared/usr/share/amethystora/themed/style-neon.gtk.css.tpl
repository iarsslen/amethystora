/* The neon desktop style in the applications, for {{ theme_name }}: tight corners, the focused window outlined and
   glowing in the theme's accent, and the controls that are on or chosen glowing too. 20-gtk-apps.sh adds the current
   style's file to ~/.config/gtk-4.0/gtk.css and ~/.config/gtk-3.0/gtk.css, which GTK reads above every theme, so
   every rule here wins over the applications' own; the shell's half is shell-styles.css. The windows' corners are the
   glass's too (modules/style.js). */

window.csd,
window.csd > decoration {
    border-radius: 10px;
}

window.csd > .titlebar,
window.csd > headerbar {
    border-top-left-radius: 10px;
    border-top-right-radius: 10px;
}

window.csd.maximized, window.csd.fullscreen, window.csd.tiled, window.csd.tiled-top, window.csd.tiled-bottom,
window.csd.tiled-left, window.csd.tiled-right,
window.csd.maximized > decoration, window.csd.fullscreen > decoration, window.csd.tiled > decoration,
window.csd.maximized > .titlebar, window.csd.fullscreen > .titlebar, window.csd.tiled > .titlebar,
window.csd.maximized > headerbar, window.csd.tiled > headerbar {
    border-radius: 0;
}

window.csd:not(.maximized):not(.fullscreen):not(.tiled):not(:backdrop),
window.csd:not(.maximized):not(.fullscreen):not(.tiled):not(:backdrop) > decoration {
    box-shadow: 0 0 0 1px rgba({{ accent_rgb }}, 0.8), 0 0 22px rgba({{ accent_rgb }}, 0.35), 0 4px 12px rgba(0, 0, 0, 0.4);
}

button:not(.circular):not(.pill):not(.titlebutton),
spinbutton,
entry,
dropdown > button,
combobox > box > button {
    border-radius: 8px;
}

popover > contents,
popover.background,
popover.menu > contents {
    border-radius: 10px;
    box-shadow: 0 0 0 1px rgba({{ accent_rgb }}, 0.6), 0 0 16px rgba({{ accent_rgb }}, 0.3);
}

.card,
list.boxed-list,
.boxed-list,
frame > border {
    border-radius: 10px;
}

button.suggested-action,
entry:focus-within,
spinbutton:focus-within,
switch:checked,
check:checked,
radio:checked {
    box-shadow: 0 0 10px rgba({{ accent_rgb }}, 0.6);
}
