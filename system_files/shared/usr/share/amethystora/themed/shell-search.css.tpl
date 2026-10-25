/* The search box (Super+Space) in the colours of {{ theme_name }}: the theme's own surface and text, where the module's
   stylesheet (stylesheets/search.css) stands in, dark with white text, until a theme has been applied. Every selector
   starts from the shell's top group, one id more than that stylesheet has, which is loaded after this one. */

#uiGroup .amethystora-search-box {
  background-color: rgba({{ popover_bg_rgb }}, 0.94);
  border-color: rgba({{ foreground_rgb }}, 0.16);
  color: {{ foreground }};
}

#uiGroup .amethystora-search-box .search-entry,
#uiGroup .amethystora-search-box .search-entry:hover,
#uiGroup .amethystora-search-box .search-entry:focus,
#uiGroup .amethystora-search-box .search-entry:focus:hover,
#uiGroup .amethystora-search-box .search-entry:insensitive,
#uiGroup .amethystora-search-box .search-entry .search-entry-icon {
  color: {{ foreground }};
}

#uiGroup .amethystora-search-box .search-entry StLabel.hint-text {
  color: rgba({{ foreground_rgb }}, {{ dim_alpha }});
}

#uiGroup .amethystora-search-box .search-section-content {
  background-color: rgba({{ foreground_rgb }}, 0.07);
  color: {{ foreground }};
}

#uiGroup .amethystora-search-box .overview-tile,
#uiGroup .amethystora-search-box .grid-search-result,
#uiGroup .amethystora-search-box .list-search-result,
#uiGroup .amethystora-search-box .search-provider-icon {
  color: {{ foreground }};
}

#uiGroup .amethystora-search-box .overview-tile:hover,
#uiGroup .amethystora-search-box .overview-tile:focus,
#uiGroup .amethystora-search-box .overview-tile:active,
#uiGroup .amethystora-search-box .grid-search-result:hover,
#uiGroup .amethystora-search-box .grid-search-result:focus,
#uiGroup .amethystora-search-box .grid-search-result:active,
#uiGroup .amethystora-search-box .list-search-result:hover,
#uiGroup .amethystora-search-box .list-search-result:focus,
#uiGroup .amethystora-search-box .list-search-result:active,
#uiGroup .amethystora-search-box .search-provider-icon:hover,
#uiGroup .amethystora-search-box .search-provider-icon:focus,
#uiGroup .amethystora-search-box .search-provider-icon:active {
  background-color: rgba({{ foreground_rgb }}, 0.09);
}

#uiGroup .amethystora-search-box .overview-tile:selected,
#uiGroup .amethystora-search-box .grid-search-result:selected,
#uiGroup .amethystora-search-box .list-search-result:selected,
#uiGroup .amethystora-search-box .search-provider-icon:selected {
  background-color: rgba({{ foreground_rgb }}, 0.18);
}
