/* What the neon style adds to its shape: the focused window outlined and glowing in the theme's accent, and the controls
   that are on or chosen glowing too. */

window.csd:not(.maximized):not(.fullscreen):not(.tiled):not(:backdrop),
window.csd:not(.maximized):not(.fullscreen):not(.tiled):not(:backdrop) > decoration {
    box-shadow: 0 0 0 1px rgba({{ accent_bg_rgb }}, 0.8), 0 0 22px rgba({{ accent_bg_rgb }}, 0.35), 0 4px 12px rgba(0, 0, 0, 0.4);
}

popover > contents,
popover.background,
popover.menu > contents {
    box-shadow: 0 0 0 1px rgba({{ accent_bg_rgb }}, 0.6), 0 0 16px rgba({{ accent_bg_rgb }}, 0.3);
}

button.suggested-action,
entry:focus-within,
spinbutton:focus-within,
switch:checked,
check:checked,
radio:checked {
    box-shadow: 0 0 10px rgba({{ accent_bg_rgb }}, 0.6);
}
