/* The phone's capsule in the top bar in the colours of {{ theme_name }}: the theme's text colour at a tenth behind the
   battery and the signal, which are drawn in the bar's own text colour. The terminal style squares every pill, this one
   too. The selectors start from the shell's top group, which the module's own stylesheet does not, so these win over
   its stand-in. */

#uiGroup .amethystora-connect-capsule { background-color: rgba({{ foreground_rgb }}, 0.1); }
#uiGroup.amethystora-style-terminal .amethystora-connect-capsule { border-radius: 0; }
