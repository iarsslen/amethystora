/* The app grid in the colours of {{ theme_name }}: the labels over the recent row and the grid in the text colour,
   dimmed; a folder's square in a veil of the text colour with a hairline of it; and the open folder a veil of the
   theme's background over the glass. Every selector carries the shell's top group, one id more than the module's own
   stylesheet (stylesheets/appgrid.css), which only stands in until a theme has been applied. */

#uiGroup .amethystora-appgrid-label { color: rgba({{ foreground_rgb }}, {{ dim_alpha }}); }

#uiGroup #overviewGroup .amethystora-appgrid-folder-icon {
  background-color: rgba({{ foreground_rgb }}, 0.12);
  border-color: rgba({{ foreground_rgb }}, 0.14);
}

#uiGroup #overviewGroup.amethystora-appgrid .app-folder-dialog {
  background-color: rgba({{ background_rgb }}, 0.55);
  border-color: rgba({{ foreground_rgb }}, 0.16);
  border-top-color: rgba({{ foreground_rgb }}, 0.45);
  color: {{ foreground }};
}

/* The apps' names on the folder's own veil, which is the theme's background, light or dark */
#uiGroup #overviewGroup.amethystora-appgrid .app-folder-dialog .overview-tile { color: {{ foreground }}; }
