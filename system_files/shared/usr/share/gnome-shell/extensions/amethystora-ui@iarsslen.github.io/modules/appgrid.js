// The app grid opens on the apps used most: a row of them under the label "Recently used", then "All apps" over GNOME's
// own grid, whose folders fill themselves from the apps' categories (the image's defaults in org.gnome.desktop.app-folders).
// The row is GNOME's own app icons, so a click, a drag and the right-click menu are GNOME's; what it holds comes from
// GNOME's own record of use, read only as the overview opens. An account that has used nothing yet sees no row and no
// labels. The folders are drawn as the image draws them: a tile with its four apps in a square, and the open folder a
// pane of glass with its name over its apps.

import Clutter from 'gi://Clutter';
import Graphene from 'gi://Graphene';
import Pango from 'gi://Pango';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as AppDisplay from 'resource:///org/gnome/shell/ui/appDisplay.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as ParentalControlsManager from 'resource:///org/gnome/shell/misc/parentalControlsManager.js';
import {InjectionManager, gettext as _} from 'resource:///org/gnome/shell/extensions/extension.js';

const MOST = 8;
// The folder tile's square, as a share of its side: the corners, the inset of the four apps and the gap between them
const TILE_RADIUS = 18 / 64;
const TILE_INSET = 9 / 64;
const TILE_GAP = 5 / 64;
const TILE_CLASS = 'amethystora-appgrid-tile';
const ICON_CLASS = 'amethystora-appgrid-folder-icon';
const GROUP_CLASS = 'amethystora-appgrid';

export class AppGrid {
    constructor(ext) {
        this._ext = ext;
    }

    enable() {
        this._settings = this._ext.getSettings('org.gnome.shell.extensions.amethystora-ui.appgrid');
        this._appDisplay = Main.overview._overview?.controls?._appDisplay ?? null;
        if (!this._appDisplay?._box || !this._appDisplay._grid) {
            console.warn('Amethystora UI: appgrid: GNOME\'s app grid is not where it was, so it is left as it is');
            this._appDisplay = null;
            return;
        }
        // The theme's colours for the folders apply only while this runs
        Main.layoutManager.overviewGroup.add_style_class_name(GROUP_CLASS);
        this._folders();
        this._settings.connectObject('changed::recent', () => this._sync(), this);
        this._sync();
    }

    disable() {
        this._settings?.disconnectObject(this);
        this._removeRow();
        this._unfolders();
        Main.layoutManager.overviewGroup.remove_style_class_name(GROUP_CLASS);
        this._appDisplay = null;
        // Disposed now rather than by the collector (dock.js says why)
        this._settings?.run_dispose();
        this._settings = null;
    }

    _sync() {
        if (this._settings.get_boolean('recent'))
            this._addRow();
        else
            this._removeRow();
    }

    // --- The recent row ----------------------------------------------------------------------------------------------

    _addRow() {
        if (this._row)
            return;
        const box = this._appDisplay._box;
        this._recentLabel = this._label(_('Recently used'));
        this._row = new St.BoxLayout({style_class: 'amethystora-appgrid-row', x_align: Clutter.ActorAlign.START});
        this._allLabel = this._label(_('All apps'));
        box.insert_child_at_index(this._recentLabel, 0);
        box.insert_child_at_index(this._row, 1);
        box.insert_child_at_index(this._allLabel, 2);
        this._icons = new Map();
        this._show(false);
        // Filled as the overview opens, and only then
        Main.overview.connectObject('showing', () => this._fill(), this);
        // The grid lays itself out again when the screen, the row or its pages change: the row follows it then
        this._appDisplay._grid.connectObject('notify::allocation', () => this._align(), this);
        this._appDisplay._grid.layout_manager.connectObject('notify::icon-size', () => this._align(), this);
        if (Main.overview.visible)
            this._fill();
    }

    _removeRow() {
        Main.overview.disconnectObject(this);
        this._appDisplay?._grid.disconnectObject(this);
        this._appDisplay?._grid.layout_manager.disconnectObject(this);
        for (const name of ['_recentLabel', '_row', '_allLabel']) {
            this[name]?.destroy();
            this[name] = null;
        }
        this._icons = null;
    }

    _label(text) {
        const label = new St.Label({
            style_class: 'amethystora-appgrid-label',
            text: text.toLocaleUpperCase(),
            x_align: Clutter.ActorAlign.START,
        });
        label.clutter_text.use_markup = false;
        // St does not count the letter spacing in the label's width
        label.clutter_text.ellipsize = Pango.EllipsizeMode.NONE;
        return label;
    }

    _show(shown) {
        for (const actor of [this._recentLabel, this._row, this._allLabel])
            actor.visible = shown;
    }

    // The apps used most, most first, that are installed, shown in the grid and allowed by Parental Controls
    _apps(count) {
        const system = Shell.AppSystem.get_default();
        const parental = ParentalControlsManager.getDefault();
        const apps = [];
        for (const used of Shell.AppUsage.get_default().get_most_used()) {
            const app = system.lookup_app(used.get_id());
            const info = app?.app_info;
            if (!info || !info.should_show() || !parental.shouldShowApp(info))
                continue;
            apps.push(app);
            if (apps.length >= count)
                break;
        }
        return apps;
    }

    _fill() {
        const layout = this._appDisplay._grid.layout_manager;
        const count = Math.min(MOST, layout.columnsPerPage || MOST);
        const apps = this._apps(count);
        const wanted = new Set(apps.map(app => app.get_id()));
        for (const [id, icon] of this._icons) {
            if (!wanted.has(id)) {
                icon.destroy();
                this._icons.delete(id);
            }
        }
        apps.forEach((app, index) => {
            let icon = this._icons.get(app.get_id());
            if (!icon) {
                // Not draggable: GNOME's grid moves only its own icons, and one of the row's dropped on it would
                // throw inside its drag and drop
                icon = new AppDisplay.AppIcon(app, {isDraggable: false, expandTitleOnHover: false});
                this._icons.set(app.get_id(), icon);
                this._row.add_child(icon);
            }
            this._row.set_child_at_index(icon, index);
        });
        this._align();
        // Shown or hidden only when that changes, so that the grid lays its pages out again only then
        if (this._row.visible !== apps.length > 0)
            this._show(apps.length > 0);
    }

    // The row in the grid's own columns and at its icon size: as far from the left and as far apart as the grid's first
    // row. Done again only when the grid itself changes (its size, or the size of its icons), never per frame.
    _align() {
        if (!this._row || !this._icons?.size)
            return;
        const layout = this._appDisplay._grid.layout_manager;
        const size = layout.fixedIconSize > 0 ? layout.fixedIconSize : layout.iconSize;
        const [first, second] = (this._appDisplay._orderedItems ?? []).filter(item => item.visible);
        const placed = first?.has_allocation() && first.width > 0;
        for (const icon of this._icons.values()) {
            if (size > 0 && icon.icon.iconSize !== size)
                icon.icon.setIconSize(size);
            if (placed && icon.width !== first.width)
                icon.set_width(first.width);
        }
        if (!placed)
            return;
        // Within the app grid, whatever the overview does to it as it opens; a later page is further right
        const box = this._appDisplay._box;
        const at = item => item.apply_relative_transform_to_point(box, new Graphene.Point3D({x: 0, y: 0, z: 0})).x;
        const left = at(first);
        if (left < 0 || left >= box.width)
            return;
        let spacing = layout.columnSpacing ?? 0;
        if (second?.has_allocation()) {
            const step = at(second) - left;
            if (step > first.width)
                spacing = step - first.width;
        }
        const pad = `padding-left: ${Math.round(left)}px;`;
        const rowStyle = `${pad} spacing: ${Math.round(spacing)}px;`;
        // Set only when it changes: a new style lays the grid out again
        if (this._row.get_style() !== rowStyle) {
            this._row.set_style(rowStyle);
            this._recentLabel.set_style(pad);
            this._allLabel.set_style(pad);
        }
    }

    // --- The folders -------------------------------------------------------------------------------------------------

    // GNOME draws a folder's four apps in a square of its own making; the image's tile is drawn round them
    _folders() {
        this._injections = new InjectionManager();
        this._injections.overrideMethod(AppDisplay.FolderView.prototype, 'createFolderIcon', original => function (size, ...rest) {
            const icon = original.call(this, size, ...rest);
            try {
                shapeFolder(icon, size);
                if (rest[0] instanceof AppDisplay.FolderIcon)
                    rest[0].add_style_class_name(TILE_CLASS);
            } catch (e) {
                console.error(`Amethystora UI: appgrid: a folder's tile: ${e.message}`);
            }
            return icon;
        });
        this._redrawFolders();
    }

    _unfolders() {
        this._injections?.clear();
        this._injections = null;
        this._redrawFolders();
    }

    // The folders already drawn, drawn again by whichever createFolderIcon is in place now
    _redrawFolders() {
        for (const item of this._appDisplay?._orderedItems ?? []) {
            if (!(item instanceof AppDisplay.FolderIcon))
                continue;
            item.remove_style_class_name(TILE_CLASS);
            item.icon?.update?.();
        }
    }
}

// The square: rounded, its four apps set in from its edges and apart by the image's measures, the whole as large as
// GNOME made it
function shapeFolder(icon, size) {
    const inset = Math.round(size * TILE_INSET);
    const gap = Math.round(size * TILE_GAP);
    const sub = Math.floor((size - 2 * inset - gap) / 2);
    icon.add_style_class_name(ICON_CLASS);
    icon.set_style(`width: ${size - 2 * inset}px; height: ${size - 2 * inset}px; padding: ${inset}px; ` +
        `border-radius: ${Math.round(size * TILE_RADIUS)}px;`);
    const layout = icon.layout_manager;
    if (layout instanceof Clutter.GridLayout) {
        layout.row_spacing = gap;
        layout.column_spacing = gap;
    }
    for (const bin of icon.get_children()) {
        bin.set_style(`width: ${sub}px; height: ${sub}px;`);
        if (bin.child instanceof St.Icon)
            bin.child.icon_size = sub;
    }
}
