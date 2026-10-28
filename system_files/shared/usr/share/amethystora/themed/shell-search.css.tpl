/* The search box (Super+Space) and Amethystora's own search sections in the colours of {{ theme_name }}: the glass's
   veil in the theme's popover colour where the glass is solid or off, the text in the theme's, the selected row in its
   accent, where the module's stylesheet (stylesheets/search.css) stands in, dark with white text, until a theme has
   been applied. Every selector starts from the shell's top group, one id more than that stylesheet has, which is
   loaded after this one. */

#uiGroup .amethystora-search-box {
  background-color: rgba({{ popover_bg_rgb }}, 0.94);
  border-color: rgba({{ foreground_rgb }}, 0.16);
  color: {{ foreground }};
}

#uiGroup .amethystora-search-box.amethystora-glass-pane {
  background-color: transparent;
  border-color: transparent;
  -amethystora-glass-edge: rgba({{ foreground_rgb }}, 0.16);
}

#uiGroup.amethystora-glass-solid .amethystora-search-box.amethystora-glass-pane {
  background-color: {{ popover_bg }};
  border-color: rgba({{ foreground_rgb }}, 0.16);
}

#uiGroup .amethystora-search-box .search-entry,
#uiGroup .amethystora-search-box .search-entry:hover,
#uiGroup .amethystora-search-box .search-entry:focus,
#uiGroup .amethystora-search-box .search-entry:focus:hover,
#uiGroup .amethystora-search-box .search-entry:insensitive {
  border-color: rgba({{ foreground_rgb }}, 0.10);
  color: {{ foreground }};
  caret-color: {{ accent_text }};
}

#uiGroup .amethystora-search-box .search-entry .search-entry-icon {
  color: {{ accent_text }};
}

#uiGroup .amethystora-search-box .search-entry StLabel.hint-text,
#uiGroup .amethystora-search-section-title,
#uiGroup .amethystora-search-section-note,
#uiGroup .amethystora-search-row-meta,
#uiGroup .amethystora-search-row-pin,
#uiGroup .amethystora-search-row-hint,
#uiGroup .amethystora-search-box .list-search-result-description,
#uiGroup .amethystora-search-box .amethystora-search-more {
  color: rgba({{ foreground_rgb }}, {{ dim_alpha }});
}

#uiGroup .amethystora-search-section-header .amethystora-search-section-tag {
  background-color: rgba({{ success_text_rgb }}, 0.18);
  color: {{ success_text }};
}

#uiGroup .amethystora-search-row,
#uiGroup .amethystora-search-box .list-search-result,
#uiGroup .amethystora-search-answer {
  color: {{ foreground }};
}

#uiGroup .amethystora-search-row:hover,
#uiGroup .amethystora-search-box .list-search-result:hover {
  background-color: rgba({{ foreground_rgb }}, 0.09);
}

#uiGroup .amethystora-search-row:selected,
#uiGroup .amethystora-search-row:focus,
#uiGroup .amethystora-search-box .list-search-result:selected,
#uiGroup .amethystora-search-box .list-search-result:focus {
  background-color: rgba({{ accent_rgb }}, 0.45);
  color: {{ foreground }};
}

#uiGroup .amethystora-search-row:selected .amethystora-search-row-hint,
#uiGroup .amethystora-search-row:focus .amethystora-search-row-hint,
#uiGroup .amethystora-search-row:selected .amethystora-search-row-meta,
#uiGroup .amethystora-search-row:focus .amethystora-search-row-meta {
  color: rgba({{ foreground_rgb }}, 0.85);
}

#uiGroup .amethystora-search-pic {
  background-color: rgba({{ foreground_rgb }}, 0.10);
}

#uiGroup .amethystora-search-pic-icon {
  color: {{ foreground }};
}

#uiGroup .amethystora-search-pic.amethystora-search-pic-agent {
  background-color: rgba({{ foreground_rgb }}, 0.18);
}

#uiGroup .amethystora-search-pic-agent .amethystora-search-pic-icon {
  color: #ffffff;
}

#uiGroup .amethystora-search-answer {
  background-color: rgba({{ accent_rgb }}, 0.32);
}

#uiGroup .amethystora-search-answer:selected,
#uiGroup .amethystora-search-answer:focus {
  box-shadow: inset 0 0 0 2px {{ accent_text }};
}

#uiGroup .amethystora-search-answer-hint {
  color: rgba({{ foreground_rgb }}, 0.9);
}

#uiGroup .amethystora-search-glance-hint {
  background-color: rgba({{ popover_bg_rgb }}, 0.94);
  color: {{ foreground }};
}

#uiGroup .amethystora-search-glance-hint.amethystora-glass-pane {
  background-color: transparent;
}

#uiGroup.amethystora-glass-solid .amethystora-search-glance-hint.amethystora-glass-pane {
  background-color: {{ popover_bg }};
}

#uiGroup .amethystora-search-key {
  background-color: rgba({{ foreground_rgb }}, 0.12);
}

#uiGroup .amethystora-search-glance-words {
  color: rgba({{ foreground_rgb }}, 0.85);
}
