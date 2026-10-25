/* The {{ style_name }} desktop style in the applications, for {{ theme_name }}: the corners of every kind of window,
   dialog, control, list, card, popover, tile, check box, switch, tooltip, toast and slider, in the style's own radii
   (STYLE_SHAPE in /usr/lib/amethystora/theme/lib.sh fills the s_ values of this file). One template draws all of
   them, so a style cannot forget a control the others have, and a grouped control is rounded at the ends of its group
   only. render_templates puts the style's own file (style-<style>.gtk.css.tpl: lines, glow, colours) after this one.
   20-gtk-apps.sh adds the result to ~/.config/gtk-4.0/gtk.css and ~/.config/gtk-3.0/gtk.css, which GTK reads above
   every theme, so every rule here wins over the applications' own whatever its selector; GTK 3 and 4 share it, and a
   selector that one of them has no node for matches nothing there. */

/* ---- Windows and dialogs ------------------------------------------------------------------------------------- */

window.csd,
window.csd > decoration {
    border-radius: {{ s_window }}px;
}

window.csd > .titlebar,
window.csd > headerbar {
    border-top-left-radius: {{ s_window }}px;
    border-top-right-radius: {{ s_window }}px;
}

window.csd.maximized, window.csd.fullscreen, window.csd.tiled, window.csd.tiled-top, window.csd.tiled-bottom,
window.csd.tiled-left, window.csd.tiled-right,
window.csd.maximized > decoration, window.csd.fullscreen > decoration, window.csd.tiled > decoration,
window.csd.maximized > .titlebar, window.csd.fullscreen > .titlebar, window.csd.tiled > .titlebar,
window.csd.maximized > headerbar, window.csd.tiled > headerbar {
    border-radius: 0;
}

window.dialog.message.csd:not(.solid-csd),
window.messagedialog.csd:not(.solid-csd),
window.dialog-window.alert.csd:not(.solid-csd),
dialog-host > dialog.alert sheet,
floating-sheet > sheet {
    border-radius: {{ s_dialog }}px;
}

/* ---- Controls ------------------------------------------------------------------------------------------------ */

button:not(.circular):not(.pill):not(.titlebutton),
splitbutton,
spinbutton,
entry,
dropdown > button,
combobox > box > button,
toggle-group,
tabbar tab,
tabbar tabbox > tabboxchild,
dnd tab,
menubar > item,
.navigation-sidebar > row,
.navigation-sidebar > child,
popover.menu modelbutton,
popover.menu list > row,
popover.menu listview > row {
    border-radius: {{ s_control }}px;
}

toggle-group > toggle {
    border-radius: {{ s_toggle }}px;
}

/* A group of linked controls is rounded at the ends of the group and straight between its members, in the style's
   corners: the rule above gave every one of them all four */
.linked:not(.vertical) > button:not(:first-child):not(:last-child),
.linked:not(.vertical) > entry:not(:first-child):not(:last-child),
.linked:not(.vertical) > spinbutton:not(:first-child):not(:last-child),
.linked:not(.vertical) > menubutton:not(:first-child):not(:last-child) > button,
.linked:not(.vertical) > combobox:not(:first-child):not(:last-child) > box > button,
.linked:not(.vertical) > dropdown:not(:first-child):not(:last-child) > button,
.linked.vertical > button:not(:first-child):not(:last-child),
.linked.vertical > entry:not(:first-child):not(:last-child),
.linked.vertical > spinbutton:not(:first-child):not(:last-child),
.linked.vertical > menubutton:not(:first-child):not(:last-child) > button,
.linked.vertical > combobox:not(:first-child):not(:last-child) > box > button,
.linked.vertical > dropdown:not(:first-child):not(:last-child) > button {
    border-radius: 0;
}

.linked:not(.vertical) > button:first-child:not(:last-child):dir(ltr),
.linked:not(.vertical) > entry:first-child:not(:last-child):dir(ltr),
.linked:not(.vertical) > spinbutton:first-child:not(:last-child):dir(ltr),
.linked:not(.vertical) > menubutton:first-child:not(:last-child):dir(ltr) > button,
.linked:not(.vertical) > combobox:first-child:not(:last-child):dir(ltr) > box > button,
.linked:not(.vertical) > dropdown:first-child:not(:last-child):dir(ltr) > button,
.linked:not(.vertical) > button:last-child:not(:first-child):dir(rtl),
.linked:not(.vertical) > entry:last-child:not(:first-child):dir(rtl),
.linked:not(.vertical) > spinbutton:last-child:not(:first-child):dir(rtl),
.linked:not(.vertical) > menubutton:last-child:not(:first-child):dir(rtl) > button,
.linked:not(.vertical) > combobox:last-child:not(:first-child):dir(rtl) > box > button,
.linked:not(.vertical) > dropdown:last-child:not(:first-child):dir(rtl) > button {
    border-radius: {{ s_control }}px 0 0 {{ s_control }}px;
}

.linked:not(.vertical) > button:last-child:not(:first-child):dir(ltr),
.linked:not(.vertical) > entry:last-child:not(:first-child):dir(ltr),
.linked:not(.vertical) > spinbutton:last-child:not(:first-child):dir(ltr),
.linked:not(.vertical) > menubutton:last-child:not(:first-child):dir(ltr) > button,
.linked:not(.vertical) > combobox:last-child:not(:first-child):dir(ltr) > box > button,
.linked:not(.vertical) > dropdown:last-child:not(:first-child):dir(ltr) > button,
.linked:not(.vertical) > button:first-child:not(:last-child):dir(rtl),
.linked:not(.vertical) > entry:first-child:not(:last-child):dir(rtl),
.linked:not(.vertical) > spinbutton:first-child:not(:last-child):dir(rtl),
.linked:not(.vertical) > menubutton:first-child:not(:last-child):dir(rtl) > button,
.linked:not(.vertical) > combobox:first-child:not(:last-child):dir(rtl) > box > button,
.linked:not(.vertical) > dropdown:first-child:not(:last-child):dir(rtl) > button {
    border-radius: 0 {{ s_control }}px {{ s_control }}px 0;
}

.linked.vertical > button:first-child:not(:last-child),
.linked.vertical > entry:first-child:not(:last-child),
.linked.vertical > spinbutton:first-child:not(:last-child),
.linked.vertical > menubutton:first-child:not(:last-child) > button,
.linked.vertical > combobox:first-child:not(:last-child) > box > button,
.linked.vertical > dropdown:first-child:not(:last-child) > button {
    border-radius: {{ s_control }}px {{ s_control }}px 0 0;
}

.linked.vertical > button:last-child:not(:first-child),
.linked.vertical > entry:last-child:not(:first-child),
.linked.vertical > spinbutton:last-child:not(:first-child),
.linked.vertical > menubutton:last-child:not(:first-child) > button,
.linked.vertical > combobox:last-child:not(:first-child) > box > button,
.linked.vertical > dropdown:last-child:not(:first-child) > button {
    border-radius: 0 0 {{ s_control }}px {{ s_control }}px;
}

/* A split button is one control of two halves: round at its two ends, straight where the halves meet. The rule that
   gave every button all four corners is more particular than a plain child selector, so these name the same things it
   leaves out */
splitbutton > button:first-child:not(:last-child):not(.circular):dir(ltr),
splitbutton > button:last-child:not(:first-child):not(.circular):dir(rtl) {
    border-radius: {{ s_control }}px 0 0 {{ s_control }}px;
}

splitbutton > button:last-child:not(:first-child):not(.circular):dir(ltr),
splitbutton > menubutton > button:not(.circular):not(.pill):dir(ltr),
splitbutton > button:first-child:not(:last-child):not(.circular):dir(rtl),
splitbutton > menubutton > button:not(.circular):not(.pill):dir(rtl) {
    border-radius: 0 {{ s_control }}px {{ s_control }}px 0;
}

check {
    border-radius: {{ s_check }}px;
}

switch {
    border-radius: {{ s_switch }}px;
}

switch > slider,
switch slider,
scale > trough > slider {
    border-radius: {{ s_knob }}px;
}

progressbar trough,
progressbar progress,
scale trough,
scale highlight,
scale fill,
levelbar:not(.discrete) block,
scrollbar > range > trough,
scrollbar > range > trough > slider {
    border-radius: {{ s_bar }}px;
}

/* ---- Lists, cards, popovers, tiles ---------------------------------------------------------------------------- */

.card,
list.boxed-list,
list.content,
list.boxed-list-separate > row,
.boxed-list,
frame,
frame > border,
menubutton.card > button {
    border-radius: {{ s_card }}px;
}

/* The rows at the ends of a list are the card's corners as well, or their hover and focus would be another shape */
list.boxed-list > row:first-child,
list.content > row:first-child {
    border-top-left-radius: {{ s_card }}px;
    border-top-right-radius: {{ s_card }}px;
}

list.boxed-list > row:last-child,
list.content > row:last-child {
    border-bottom-left-radius: {{ s_card }}px;
    border-bottom-right-radius: {{ s_card }}px;
}

popover > contents,
popover.background,
popover.menu > contents,
menubar > item popover.menu popover.menu > contents {
    border-radius: {{ s_popover }}px;
}

flowbox > flowboxchild,
gridview > child,
filechooser gridview > child,
iconview:selected {
    border-radius: {{ s_tile }}px;
}

tooltip,
tooltip.background {
    border-radius: {{ s_tooltip }}px;
}

toast {
    border-radius: {{ s_toast }}px;
}
