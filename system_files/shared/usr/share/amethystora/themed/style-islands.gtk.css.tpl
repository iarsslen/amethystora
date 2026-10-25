/* The islands desktop style in the applications, for {{ theme_name }}: soft, generous corners on the windows, buttons,
   entries, popovers and cards. 20-gtk-apps.sh adds the current style's file to ~/.config/gtk-4.0/gtk.css and
   ~/.config/gtk-3.0/gtk.css, which GTK reads above every theme, so every rule here wins over the applications' own;
   the shell's half is shell-styles.css. The windows' corners are the glass's too (modules/style.js). */

window.csd,
window.csd > decoration {
    border-radius: 16px;
}

window.csd > .titlebar,
window.csd > headerbar {
    border-top-left-radius: 16px;
    border-top-right-radius: 16px;
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
combobox > box > button {
    border-radius: 12px;
}

popover > contents,
popover.background,
popover.menu > contents {
    border-radius: 18px;
}

.card,
list.boxed-list,
.boxed-list,
frame > border {
    border-radius: 16px;
}

check {
    border-radius: 7px;
}

tooltip,
tooltip.background {
    border-radius: 10px;
}
