/* The hairline desktop style in the applications, for {{ theme_name }}: crisp corners and thin lines on the windows,
   buttons, entries, popovers, cards and controls. 20-gtk-apps.sh adds the current style's file to
   ~/.config/gtk-4.0/gtk.css and ~/.config/gtk-3.0/gtk.css, which GTK reads above every theme, so every rule here wins
   over the applications' own; the shell's half is shell-styles.css. The windows' corners are the glass's too
   (modules/style.js). */

window.csd,
window.csd > decoration {
    border-radius: 6px;
}

window.csd > .titlebar,
window.csd > headerbar {
    border-top-left-radius: 6px;
    border-top-right-radius: 6px;
}

window.csd.maximized, window.csd.fullscreen, window.csd.tiled, window.csd.tiled-top, window.csd.tiled-bottom,
window.csd.tiled-left, window.csd.tiled-right,
window.csd.maximized > decoration, window.csd.fullscreen > decoration, window.csd.tiled > decoration,
window.csd.maximized > .titlebar, window.csd.fullscreen > .titlebar, window.csd.tiled > .titlebar,
window.csd.maximized > headerbar, window.csd.tiled > headerbar {
    border-radius: 0;
}

button:not(.circular):not(.pill):not(.titlebutton),
spinbutton,
entry,
dropdown > button,
combobox > box > button,
switch {
    border-radius: 4px;
}

switch > slider,
switch slider {
    border-radius: 3px;
}

popover > contents,
popover.background,
popover.menu > contents {
    border-radius: 6px;
    box-shadow: 0 0 0 1px rgba({{ foreground_rgb }}, 0.14), 0 4px 12px rgba(0, 0, 0, 0.18);
}

.card,
list.boxed-list,
.boxed-list,
frame > border {
    border-radius: 6px;
    box-shadow: 0 0 0 1px rgba({{ foreground_rgb }}, 0.12);
}

check {
    border-radius: 3px;
}

progressbar trough,
progressbar progress,
scale trough,
scale highlight,
levelbar block {
    border-radius: 2px;
}

tooltip,
tooltip.background {
    border-radius: 4px;
}
