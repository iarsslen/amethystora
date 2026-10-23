// Where a tray item's picture comes from. An item names an icon, gives a file, or sends the pixels themselves; a
// name that is found always wins over pixels. Names are looked up in the item's own folder when it gives one the
// icon theme does not already search, else in the icon theme. A file the user's programs can write is read afresh
// each time, so that a program rewriting the same file shows the new picture, and a wide one (a graph) keeps its
// width.

import Cogl from 'gi://Cogl';
import GdkPixbuf from 'gi://GdkPixbuf';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';

// A picture this much wider than tall is shown at its own width
const WIDE = 1.5;
const IMAGE_SUFFIX = /\.(png|svg)$/i;

/**
 * Pixels as the shell draws them, from a pixmap property (a(iiay): width, height, ARGB32 in network byte order,
 * which is Cogl's ARGB_8888 byte for byte). Of the sizes given, the smallest at least as big as wanted, else the
 * largest.
 *
 * @param {GLib.Variant} pixmaps - the property's value
 * @param {number} wanted - the size in device pixels
 * @returns {St.ImageContent|null}
 */
export function pixmapContent(pixmaps, wanted) {
    let best = null;
    for (let i = 0; i < pixmaps.n_children(); i++) {
        const child = pixmaps.get_child_value(i);
        const width = child.get_child_value(0).get_int32();
        const height = child.get_child_value(1).get_int32();
        if (width <= 0 || height <= 0)
            continue;
        const area = width * height;
        const bigEnough = width >= wanted && height >= wanted;
        if (!best ||
            (bigEnough && (!best.bigEnough || area < best.area)) ||
            (!bigEnough && !best.bigEnough && area > best.area))
            best = {child, width, height, area, bigEnough};
    }
    if (!best)
        return null;

    const bytes = best.child.get_child_value(2).get_data_as_bytes();
    if (bytes.get_size() < best.width * best.height * 4)
        return null;
    return imageContent(bytes, Cogl.PixelFormat.ARGB_8888, best.width, best.height, best.width * 4);
}

function imageContent(bytes, format, width, height, rowstride) {
    const content = St.ImageContent.new_with_preferred_size(width, height);
    try {
        const cogl = global.stage.context.get_backend().get_cogl_context();
        content.set_bytes(cogl, bytes, format, width, height, rowstride);
    } catch {
        return null;
    }
    return content;
}

/**
 * A decoded picture (PNG, SVG, anything GdkPixbuf reads), scaled to `height` device pixels and, unless it is wide,
 * to the same width at most.
 *
 * @param {GLib.Bytes} bytes - the encoded picture
 * @param {number} height - the height wanted, in device pixels
 * @returns {{content: St.ImageContent, width: number, height: number, wide: boolean}|null}
 */
export function decodedContent(bytes, height) {
    const loader = new GdkPixbuf.PixbufLoader();
    let wide = false;
    loader.connect('size-prepared', (l, width, naturalHeight) => {
        if (width <= 0 || naturalHeight <= 0)
            return;
        wide = width >= WIDE * naturalHeight;
        const scale = wide ? height / naturalHeight : height / Math.max(width, naturalHeight);
        l.set_size(Math.max(1, Math.round(width * scale)), Math.max(1, Math.round(naturalHeight * scale)));
    });
    let pixbuf;
    try {
        loader.write_bytes(bytes);
        loader.close();
        pixbuf = loader.get_pixbuf();
    } catch {
        try {
            loader.close();
        } catch {}
        return null;
    }
    if (!pixbuf)
        return null;
    const format = pixbuf.get_has_alpha() ? Cogl.PixelFormat.RGBA_8888 : Cogl.PixelFormat.RGB_888;
    const content = imageContent(pixbuf.read_pixel_bytes(), format, pixbuf.get_width(), pixbuf.get_height(),
        pixbuf.get_rowstride());
    return content ? {content, width: pixbuf.get_width(), height: pixbuf.get_height(), wide} : null;
}

function readFile(file) {
    return new Promise((resolve, reject) => {
        file.load_contents_async(null, (f, result) => {
            try {
                resolve(f.load_contents_finish(result)[1]);
            } catch (e) {
                reject(e);
            }
        });
    });
}

// The places the account's own programs write to: their files may change under the same name
function userPlaces() {
    const places = [
        GLib.get_home_dir(), GLib.get_tmp_dir(), '/var/tmp', GLib.get_user_runtime_dir(),
        GLib.get_user_cache_dir(), GLib.get_user_data_dir(), GLib.get_user_config_dir(),
    ];
    for (const key of Object.keys(GLib.UserDirectory)) {
        const dir = GLib.UserDirectory[key];
        if (typeof dir === 'number' && dir < GLib.UserDirectory.N_DIRECTORIES)
            places.push(GLib.get_user_special_dir(dir));
    }
    return places.filter(place => place && place !== '/');
}

export class IconFinder {
    constructor() {
        // The shell's icon theme, to ask whether a name is in it; it follows the icon theme setting by itself
        this._theme = new St.IconTheme();
        this._places = userPlaces();
    }

    destroy() {
        this._theme = null;
    }

    /**
     * The picture for one of an item's icons.
     *
     * @param {import('./item.js').Item} item - the tray item
     * @param {string} kind - '', 'Attention' or 'Overlay'
     * @param {object} look - how the icon is drawn
     * @param {number} look.size - in logical pixels
     * @param {number} look.scale - the shell's scale factor
     * @param {number} look.resourceScale - the actor's resource scale
     * @param {St.IconStyle} look.style - the panel's icon style
     * @param {boolean} look.rtl - whether the text runs right to left
     * @returns {Promise<{gicon: Gio.Icon}|{wide: St.ImageContent, width: number, height: number}|null>}
     */
    async find(item, kind, look) {
        const wanted = Math.ceil(look.size * look.scale * look.resourceScale);
        const name = this._cleanName(item.props[`${kind}IconName`]);
        if (name) {
            const found = await this._fromName(name, item.props.IconThemePath, wanted, look);
            if (found)
                return found;
        }

        const pixmapName = `${kind}IconPixmap`;
        const pixmaps = await item.pixmap(pixmapName);
        if (!pixmaps)
            return null;
        const content = pixmapContent(pixmaps, wanted);
        // Drawn once, the shell's copy of the pixels is enough until the size changes
        item.dropPixmap(pixmapName);
        return content ? {gicon: content} : null;
    }

    // Only a final .png or .svg goes: some programs give a file name for an icon name
    _cleanName(name) {
        if (typeof name !== 'string' || !name)
            return null;
        return name.startsWith('/') ? name : name.replace(IMAGE_SUFFIX, '');
    }

    // A picture, or a promise of one, for a name
    _fromName(name, themePath, wanted, look) {
        if (name.startsWith('/'))
            return this._fromFile(name, wanted);

        if (themePath && typeof themePath === 'string' && !this._theme.get_search_path().includes(themePath)) {
            const file = this._lookInFolder(name, themePath, look);
            return file ? this._fromFile(file, wanted) : null;
        }

        return this._theme.has_icon(name) ? {gicon: new Gio.ThemedIcon({name})} : null;
    }

    // The item's own folder as an icon theme of its own, made afresh each time: a program may add files to it
    _lookInFolder(name, folder, look) {
        const theme = new St.IconTheme();
        theme.set_search_path([folder]);
        let flags = St.IconLookupFlags.GENERIC_FALLBACK;
        if (look.style === St.IconStyle.REGULAR)
            flags |= St.IconLookupFlags.FORCE_REGULAR;
        else if (look.style === St.IconStyle.SYMBOLIC)
            flags |= St.IconLookupFlags.FORCE_SYMBOLIC;
        flags |= look.rtl ? St.IconLookupFlags.DIR_RTL : St.IconLookupFlags.DIR_LTR;
        const scale = Math.max(1, Math.ceil(look.scale * look.resourceScale));
        const info = theme.lookup_icon_for_scale(name, look.size, scale, flags);
        return info?.get_filename() ?? null;
    }

    async _fromFile(path, wanted) {
        const file = Gio.File.new_for_path(path);
        const canonical = file.get_path();
        const mine = this._places.some(place => canonical === place || canonical.startsWith(`${place}/`));
        // A symbolic file is left to the shell, which colours it like the panel's text
        if (!mine || /-symbolic(\.symbolic)?\.(svg|png)$/.test(canonical))
            return {gicon: new Gio.FileIcon({file})};

        let bytes;
        try {
            bytes = await readFile(file);
        } catch {
            return null;
        }
        const decoded = decodedContent(bytes, wanted);
        if (!decoded)
            return null;
        return decoded.wide ? {wide: decoded.content, width: decoded.width, height: decoded.height}
            : {gicon: decoded.content};
    }
}
