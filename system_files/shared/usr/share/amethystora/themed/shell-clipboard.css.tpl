/* The clipboard history's menu in the colours of {{ theme_name }}. The extension (amethystora-clipboard) draws its
   quieter text, tags, buttons and previews in white at some alpha, which is right on a dark glass and unreadable on a
   light one; here they are the theme's text colour, the dimmed ones at the strength that reads. Every selector starts
   from the shell's top group, one id more than the extension's own stylesheet. */

#uiGroup .clipboard-indicator-hbox.private-mode {
  color: rgba({{ foreground_rgb }}, 0.5);
}

#uiGroup .clipboard-indicator-empty-state {
  color: rgba({{ foreground_rgb }}, {{ dim_alpha }});
}

#uiGroup .ci-main-menu-section StButton.ci-pin-btn {
  color: rgba({{ foreground_rgb }}, {{ dim_alpha }});
}

#uiGroup .ci-tag-label {
  color: rgba({{ foreground_rgb }}, {{ dim_alpha }});
  background-color: rgba({{ foreground_rgb }}, 0.1);
}

#uiGroup .ci-edit-textbox {
  background-color: rgba({{ foreground_rgb }}, 0.1);
  color: {{ foreground }};
}

#uiGroup .clipboard-menu-img-preview,
#uiGroup .clipboard-indicator-img-preview {
  border-color: {{ outline }};
}
