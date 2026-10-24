/* The window buttons of the GTK 3 applications, Firefox's among them, drawn as the GTK 4 ones are
   (window-controls-gtk4.css): three lights in Amethystora's red, amber and green, each glyph showing while the
   pointer is over its button, faint in a window in the background. GTK 3 has no icon size in its stylesheets,
   so the 16 px glyph is drawn at 10. Rendered for {{ theme_name }}; 20-gtk-apps.sh puts it into
   ~/.config/gtk-3.0/gtk.css, which GTK reads above every theme. */

/* The button itself is only the 24 px target round the light (16 px of image and 4 px of padding); the light is
   its image, so that the ring and the glow follow the 16 px circle and not the button's box, which GTK 3 draws
   a box-shadow round */
button.titlebutton.close,
button.titlebutton.minimize,
button.titlebutton.maximize {
    min-width: 16px;
    min-height: 16px;
    padding: 4px;
    margin: 0;
    border: none;
    background: none;
    box-shadow: none;
    text-shadow: none;
    -gtk-icon-shadow: none;
}

/* The light. The glyph is the image itself, which a theme may colour on its own (Sweet makes every child of a title
   button transparent), so it is styled here rather than left to inherit from the button */
button.titlebutton.close image,
button.titlebutton.minimize image,
button.titlebutton.maximize image {
    min-width: 16px;
    min-height: 16px;
    padding: 0;
    border-radius: 100%;
    color: transparent;
    background-image: linear-gradient(to bottom, rgba(255, 255, 255, 0.32), rgba(255, 255, 255, 0) 62%);
    box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.22);
    -gtk-icon-shadow: none;
    -gtk-icon-transform: scale(0.625);
    transition: background-color 150ms ease-out, box-shadow 150ms ease-out, color 120ms ease-out;
}

button.titlebutton.close image {
    background-color: #f2566a;
}

button.titlebutton.minimize image {
    background-color: #f4b740;
}

button.titlebutton.maximize image {
    background-color: #3fca7e;
}

button.titlebutton.close:hover image,
button.titlebutton.minimize:hover image,
button.titlebutton.maximize:hover image {
    color: rgba(0, 0, 0, 0.62);
}

button.titlebutton.close:hover image {
    box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.22), 0 0 6px 1px rgba(242, 86, 106, 0.6);
}

button.titlebutton.minimize:hover image {
    box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.22), 0 0 6px 1px rgba(244, 183, 64, 0.6);
}

button.titlebutton.maximize:hover image {
    box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.22), 0 0 6px 1px rgba(63, 202, 126, 0.6);
}

button.titlebutton.close:active image {
    background-color: shade(#f2566a, 0.82);
}

button.titlebutton.minimize:active image {
    background-color: shade(#f4b740, 0.82);
}

button.titlebutton.maximize:active image {
    background-color: shade(#3fca7e, 0.82);
}

/* A window in the background */
button.titlebutton.close:backdrop image,
button.titlebutton.minimize:backdrop image,
button.titlebutton.maximize:backdrop image {
    background-color: rgba({{ foreground_rgb }}, 0.2);
    background-image: none;
    box-shadow: inset 0 0 0 1px rgba({{ foreground_rgb }}, 0.12);
}

button.titlebutton.close:backdrop:hover image {
    background-color: #f2566a;
}

button.titlebutton.minimize:backdrop:hover image {
    background-color: #f4b740;
}

button.titlebutton.maximize:backdrop:hover image {
    background-color: #3fca7e;
}
