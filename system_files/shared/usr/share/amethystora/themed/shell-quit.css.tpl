/* Force quit in the colours of {{ theme_name }} (modules/quit.js): the list's picked row on the accent at .4, the
   numbers in the accent's text colour, Not responding in the warning colour, Force quit in the error colour, Wait (the
   safe answer) filled with the text colour, the dimmed words at the board's strength, and GNOME's not-responding dialog
   on the theme's dialog colour. The selectors start from the shell's top group, so these win over the module's own
   stand-ins. */

#uiGroup .amethystora-quit-title,
#uiGroup .amethystora-quit-line,
#uiGroup .amethystora-quit-frozen-title { color: {{ foreground }}; }
#uiGroup .amethystora-quit-key,
#uiGroup .amethystora-quit-text,
#uiGroup .amethystora-quit-frozen-text { color: rgba({{ foreground_rgb }}, 0.85); }
#uiGroup .amethystora-quit-columns { color: rgba({{ foreground_rgb }}, 0.65); }
#uiGroup .amethystora-quit-number { color: {{ accent_text }}; }
#uiGroup .amethystora-quit-columns .amethystora-quit-number { color: rgba({{ foreground_rgb }}, 0.65); }
#uiGroup .amethystora-quit-row:hover { background-color: rgba({{ foreground_rgb }}, 0.06); }
#uiGroup .amethystora-quit-row:checked,
#uiGroup .amethystora-quit-row:checked:hover { background-color: rgba({{ accent_bg_rgb }}, 0.4); }
#uiGroup .amethystora-quit-row:focus { box-shadow: inset 0 0 0 2px rgba({{ accent_text_rgb }}, 0.7); }
#uiGroup .amethystora-quit-frozen-badge {
  background-color: rgba({{ warning_bg_rgb }}, 0.3);
  color: {{ warning_text }};
}

#uiGroup .modal-dialog .modal-dialog-button-box .modal-dialog-button.amethystora-quit-button {
  background-color: rgba({{ foreground_rgb }}, 0.08);
  border-color: rgba({{ foreground_rgb }}, 0.14);
  color: {{ foreground }};
}
#uiGroup .modal-dialog .modal-dialog-button-box .modal-dialog-button.amethystora-quit-button:hover,
#uiGroup .modal-dialog .modal-dialog-button-box .modal-dialog-button.amethystora-quit-button:focus {
  background-color: rgba({{ foreground_rgb }}, 0.16);
}
#uiGroup .modal-dialog .modal-dialog-button-box .modal-dialog-button.amethystora-quit-primary,
#uiGroup .modal-dialog .modal-dialog-button-box .modal-dialog-button.amethystora-quit-primary:hover,
#uiGroup .modal-dialog .modal-dialog-button-box .modal-dialog-button.amethystora-quit-primary:focus {
  background-color: {{ foreground }};
  border-color: {{ foreground }};
  color: {{ background }};
}
#uiGroup .modal-dialog .modal-dialog-button-box .modal-dialog-button.amethystora-quit-bad {
  background-color: rgba({{ error_bg_rgb }}, 0.3);
  border-color: rgba({{ error_bg_rgb }}, 0.6);
  color: {{ foreground }};
}
#uiGroup .modal-dialog .modal-dialog-button-box .modal-dialog-button.amethystora-quit-bad:hover,
#uiGroup .modal-dialog .modal-dialog-button-box .modal-dialog-button.amethystora-quit-bad:focus {
  background-color: rgba({{ error_bg_rgb }}, 0.45);
}

#uiGroup .modal-dialog.close-dialog.amethystora-quit-frozen {
  background-color: rgba({{ dialog_bg_rgb }}, 0.94);
  border: 1px solid rgba({{ foreground_rgb }}, 0.16);
  color: {{ foreground }};
}
#uiGroup .amethystora-quit-ask { color: {{ accent_text }}; }
#uiGroup .amethystora-quit-ask:hover,
#uiGroup .amethystora-quit-ask:focus { background-color: rgba({{ foreground_rgb }}, 0.08); }
