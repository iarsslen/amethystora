/* The terminal desktop style in the applications, for {{ theme_name }}: square everything, and thin lines round the
   entries, popovers and cards. 20-gtk-apps.sh adds the current style's file to ~/.config/gtk-4.0/gtk.css and
   ~/.config/gtk-3.0/gtk.css, which GTK reads above every theme, so every rule here wins over the applications' own,
   whatever its selector; the window buttons' lights stay round, their own rules being more particular. The shell's
   half is shell-styles.css. */

* {
    border-radius: 0;
}

entry,
spinbutton,
popover > contents,
popover.background,
.card,
list.boxed-list,
.boxed-list,
frame > border {
    box-shadow: 0 0 0 1px rgba({{ foreground_rgb }}, 0.3);
}

entry:focus-within,
spinbutton:focus-within {
    box-shadow: 0 0 0 1px {{ accent }};
}

window.csd:not(.maximized):not(.fullscreen):not(.tiled),
window.csd:not(.maximized):not(.fullscreen):not(.tiled) > decoration {
    box-shadow: 0 0 0 1px rgba({{ foreground_rgb }}, 0.35), 0 6px 18px rgba(0, 0, 0, 0.3);
}
