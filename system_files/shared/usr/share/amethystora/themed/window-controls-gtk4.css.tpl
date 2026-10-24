/* The window buttons of the GTK 4 and libadwaita applications, as Amethystora draws them: three lights,
   close, minimize and maximize, in Amethystora's own red, amber and green. They are the same in every theme,
   because the palettes' red, yellow and green slots are not always those colours (matte-black's yellow is a
   red, rose-pine-dawn's green a blue), and a light has to say what it does at a glance. Each glyph shows while
   the pointer is over the buttons, and a window in the background turns its lights to the theme's foreground,
   faint, until the pointer comes back. Rendered for {{ theme_name }}; 20-gtk-apps.sh puts it into
   ~/.config/gtk-4.0/gtk.css, which GTK reads above every theme. The Amethystora apps draw the same lights in
   apps/common/src/style.css. */

windowcontrols {
    border-spacing: 0;
}

/* The button itself is only the 24 px target round the light (16 px of content and 4 px of padding). A theme's
   stylesheet imported above it, in this same file, competes by specificity rather than by priority, so every
   state a theme styles is named here as specifically: Sweet draws its own lights as pictures on these. */
windowcontrols > button.close,
windowcontrols > button.close:hover,
windowcontrols > button.close:active,
windowcontrols > button.close:focus,
windowcontrols > button.close:backdrop,
windowcontrols > button.close:backdrop:hover,
windowcontrols > button.minimize,
windowcontrols > button.minimize:hover,
windowcontrols > button.minimize:active,
windowcontrols > button.minimize:focus,
windowcontrols > button.minimize:backdrop,
windowcontrols > button.minimize:backdrop:hover,
windowcontrols > button.maximize,
windowcontrols > button.maximize:hover,
windowcontrols > button.maximize:active,
windowcontrols > button.maximize:focus,
windowcontrols > button.maximize:backdrop,
windowcontrols > button.maximize:backdrop:hover {
    min-width: 16px;
    min-height: 16px;
    padding: 4px;
    margin: 0;
    border: none;
    background: none;
    box-shadow: none;
}

/* The light is the button's image: 10 px of glyph and 3 px around it make 16 px */
windowcontrols > button > image {
    padding: 3px;
    -gtk-icon-size: 10px;
    border-radius: 100%;
    color: transparent;
    background-image: linear-gradient(to bottom, rgba(255, 255, 255, 0.32), rgba(255, 255, 255, 0) 62%);
    box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.22);
    transition: background-color 150ms ease-out, box-shadow 150ms ease-out, color 120ms ease-out;
}

windowcontrols > button.close > image {
    background-color: #f2566a;
}

windowcontrols > button.minimize > image {
    background-color: #f4b740;
}

windowcontrols > button.maximize > image {
    background-color: #3fca7e;
}

windowcontrols:hover > button > image {
    color: rgba(0, 0, 0, 0.62);
}

windowcontrols > button.close:hover > image {
    box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.22), 0 0 6px 1px rgba(242, 86, 106, 0.6);
}

windowcontrols > button.minimize:hover > image {
    box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.22), 0 0 6px 1px rgba(244, 183, 64, 0.6);
}

windowcontrols > button.maximize:hover > image {
    box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.22), 0 0 6px 1px rgba(63, 202, 126, 0.6);
}

windowcontrols > button.close:active > image {
    background-color: shade(#f2566a, 0.82);
}

windowcontrols > button.minimize:active > image {
    background-color: shade(#f4b740, 0.82);
}

windowcontrols > button.maximize:active > image {
    background-color: shade(#3fca7e, 0.82);
}

/* A window in the background */
windowcontrols > button:backdrop > image {
    background-color: rgba({{ foreground_rgb }}, 0.2);
    background-image: none;
    box-shadow: inset 0 0 0 1px rgba({{ foreground_rgb }}, 0.12);
}

windowcontrols:hover > button.close:backdrop > image {
    background-color: #f2566a;
}

windowcontrols:hover > button.minimize:backdrop > image {
    background-color: #f4b740;
}

windowcontrols:hover > button.maximize:backdrop > image {
    background-color: #3fca7e;
}
