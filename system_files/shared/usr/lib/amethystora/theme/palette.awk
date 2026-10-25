# The palette layer's colours, worked out from a theme's colors.toml (lib.sh's derive_palette feeds it key=value lines
# and render_templates puts what it prints into every template). A theme gives a ground, a text colour, an accent and
# the slots of a terminal's palette; an interface needs more, and each has to be readable on what it is drawn on:
#
#   window_bg view_bg headerbar_bg sidebar_bg card_bg popover_bg dialog_bg   the surfaces, from the ground
#   accent_bg accent_fg                  the accent as a fill and the label on it (4.5:1: the accent is deepened or
#                                        lightened, in lightness only, until white or the theme's own colours reach it)
#   accent_text                          the accent as text on every surface (4.5:1)
#   destructive_bg destructive_fg        the same for a destructive button
#   destructive_text success_text warning_text error_text     status colours as text on every surface (4.5:1)
#   success_bg success_fg warning_bg warning_fg error_bg error_fg      and as fills, each with a label on it (4.5:1)
#   outline                              the line a control or card is drawn with, 3:1 on every surface
#   dim_opacity dim_alpha                how much of the text a dimmed label keeps, in percent and as an alpha (4.5:1 on
#                                        every surface)
#   segment1_bg segment1_fg ... segment6_bg segment6_fg    the six colours the segments style's bar is drawn in (the
#                                        accent and the palette's colours 5, 2, 3, 6 and 1), each with a label on it
#
# A colour is only ever moved in OKLab lightness, so its hue stays the theme's. Success, warning and error are the
# palette's green, yellow and red slots (color2, color3, color1), or the theme's own success, warning and error keys
# when those slots are not those colours (Matte Black's, Rose Pine Dawn's). Input, one per line on stdin:
# background, foreground, accent, color1-6, success, warning, error and light (1 for a light theme).

function hexval(s,   i, n) {
    s = tolower(s)
    n = 0
    for (i = 1; i <= length(s); i++)
        n = n * 16 + index("0123456789abcdef", substr(s, i, 1)) - 1
    return n
}
function red(h)   { return hexval(substr(h, 2, 2)) }
function green(h) { return hexval(substr(h, 4, 2)) }
function blue(h)  { return hexval(substr(h, 6, 2)) }
function lin(v)   { v = v / 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4 }
function unlin(v) {
    v = v <= 0.0031308 ? 12.92 * v : 1.055 * v ^ (1 / 2.4) - 0.055
    return v < 0 ? 0 : (v > 1 ? 1 : v)
}
function rgb(r, g, b) { return sprintf("#%02x%02x%02x", int(r + 0.5), int(g + 0.5), int(b + 0.5)) }
function lum(h)   { return 0.2126 * lin(red(h)) + 0.7152 * lin(green(h)) + 0.0722 * lin(blue(h)) }
function cr(a, b,   x, y, t) {
    x = lum(a); y = lum(b)
    if (x < y) { t = x; x = y; y = t }
    return (x + 0.05) / (y + 0.05)
}
function mix(a, b, t) {
    return rgb(red(a) * (1 - t) + red(b) * t, green(a) * (1 - t) + green(b) * t, blue(a) * (1 - t) + blue(b) * t)
}
function cbrt(x) { return x < 0 ? -exp(log(-x) / 3) : (x == 0 ? 0 : exp(log(x) / 3)) }

# OKLab, the colour and back (Björn Ottosson's matrices, public domain), through the globals OL, OA and OB
function to_oklab(h,   r, g, b, l, m, s) {
    r = lin(red(h)); g = lin(green(h)); b = lin(blue(h))
    l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    OL = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s
    OA = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s
    OB = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
}
function from_oklab(L, a, b,   l, m, s) {
    l = L + 0.3963377774 * a + 0.2158037573 * b; l = l * l * l
    m = L - 0.1055613458 * a - 0.0638541728 * b; m = m * m * m
    s = L - 0.0894841775 * a - 1.291485548 * b;  s = s * s * s
    return rgb(255 * unlin(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
        255 * unlin(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
        255 * unlin(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s))
}

# Whether h reaches `target`:1 on every surface of GROUND
function reads(h, target,   k) {
    for (k = 1; k <= NGROUND; k++)
        if (cr(h, GROUND[k]) < target)
            return 0
    return 1
}

# The colour moved in lightness until it reaches `target`:1 on every surface: lighter on dark surfaces, darker on light
function reach(h, target,   k, dir, i, L, a, b) {
    dir = 1
    for (k = 1; k <= NGROUND; k++)
        if (lum(GROUND[k]) >= 0.18)
            dir = -1
    to_oklab(h)
    L = OL; a = OA; b = OB
    for (i = 0; i < 80 && !reads(from_oklab(L, a, b), target); i++)
        L += dir * 0.01
    return from_oklab(L, a, b)
}

# The first of white, the theme's ground and its text that a label can be in on `fill` at 4.5:1, or "" when none can
function label_on(fill) {
    if (cr("#ffffff", fill) >= 4.5) return "#ffffff"
    if (cr(BG, fill) >= 4.5) return BG
    if (cr(FG, fill) >= 4.5) return FG
    return ""
}

# A fill and its label: the fill as it is when a label reaches 4.5:1 on it, else moved in lightness, away from the
# label that comes nearest, until one does. PAIR_BG and PAIR_FG are the answer.
function pair(fill,   best, bestc, c, i, L, a, b, dir) {
    PAIR_BG = fill
    PAIR_FG = label_on(fill)
    if (PAIR_FG != "")
        return
    bestc = 0
    best = "#ffffff"
    c = cr("#ffffff", fill); if (c > bestc) { bestc = c; best = "#ffffff" }
    c = cr(BG, fill);        if (c > bestc) { bestc = c; best = BG }
    c = cr(FG, fill);        if (c > bestc) { bestc = c; best = FG }
    dir = lum(best) > lum(fill) ? -1 : 1
    to_oklab(fill)
    L = OL; a = OA; b = OB
    for (i = 0; i < 60 && PAIR_FG == ""; i++) {
        L += dir * 0.01
        PAIR_BG = from_oklab(L, a, b)
        PAIR_FG = label_on(PAIR_BG)
    }
    if (PAIR_FG == "")
        PAIR_FG = best
}

# The first strength, from `from` to `to` in steps of `step` (percent), at which the text mixed into every surface
# (a dimmed label over each) reaches `target`:1 on it; or, for a line, the ground mixed with the text (one colour for
# every surface to be drawn on). `to` when none does.
function strength(from, to, step, target, line,   p, k, ok) {
    for (p = from; p <= to; p += step) {
        ok = 1
        for (k = 1; k <= NGROUND; k++)
            if (cr(line ? mix(BG, FG, p / 100) : mix(GROUND[k], FG, p / 100), GROUND[k]) < target)
                ok = 0
        if (ok)
            return p
    }
    return to
}

BEGIN { FS = "=" }
{ IN[$1] = tolower($2) }
END {
    BG = IN["background"]; FG = IN["foreground"]
    light = IN["light"] == 1
    window = BG
    if (light) {
        view = mix(BG, "#ffffff", 0.55); headerbar = mix(BG, "#ffffff", 0.35); sidebar = mix(BG, FG, 0.05)
        card = mix(BG, "#ffffff", 0.7); popover = mix(BG, "#ffffff", 0.75); dialog = BG
    } else {
        view = mix(BG, "#000000", 0.18); headerbar = mix(BG, FG, 0.06); sidebar = mix(BG, FG, 0.035)
        card = mix(BG, FG, 0.07); popover = mix(BG, FG, 0.1); dialog = mix(BG, FG, 0.08)
    }
    NGROUND = 7
    GROUND[1] = window; GROUND[2] = view; GROUND[3] = headerbar; GROUND[4] = sidebar
    GROUND[5] = card; GROUND[6] = popover; GROUND[7] = dialog

    pair(IN["accent"]);   accent_bg = PAIR_BG; accent_fg = PAIR_FG
    pair(IN["color1"]);   destructive_bg = PAIR_BG; destructive_fg = PAIR_FG
    success = IN["success"] != "" ? IN["success"] : IN["color2"]
    warning = IN["warning"] != "" ? IN["warning"] : IN["color3"]
    error = IN["error"] != "" ? IN["error"] : IN["color1"]

    printf "window_bg=%s\nview_bg=%s\nheaderbar_bg=%s\nsidebar_bg=%s\ncard_bg=%s\npopover_bg=%s\ndialog_bg=%s\n",
        window, view, headerbar, sidebar, card, popover, dialog
    printf "accent_bg=%s\naccent_fg=%s\naccent_text=%s\n", accent_bg, accent_fg, reach(IN["accent"], 4.5)
    printf "destructive_bg=%s\ndestructive_fg=%s\ndestructive_text=%s\n", destructive_bg, destructive_fg, reach(IN["color1"], 4.5)
    printf "success_text=%s\nwarning_text=%s\nerror_text=%s\n", reach(success, 4.5), reach(warning, 4.5), reach(error, 4.5)
    pair(success); printf "success_bg=%s\nsuccess_fg=%s\n", PAIR_BG, PAIR_FG
    pair(warning); printf "warning_bg=%s\nwarning_fg=%s\n", PAIR_BG, PAIR_FG
    pair(error);   printf "error_bg=%s\nerror_fg=%s\n", PAIR_BG, PAIR_FG
    printf "outline=%s\n", mix(BG, FG, strength(30, 90, 5, 3, 1) / 100)
    dim = strength(55, 95, 5, 4.5, 0)
    printf "dim_opacity=%d\ndim_alpha=%.2f\n", dim, dim / 100
    split("accent color5 color2 color3 color6 color1", SEGMENT, " ")
    for (i = 1; i <= 6; i++) {
        pair(IN[SEGMENT[i]])
        printf "segment%d_bg=%s\nsegment%d_fg=%s\n", i, PAIR_BG, i, PAIR_FG
    }
}
