// The places on the dock that are not apps: each drive that is plugged in and mounted, and the trash. A Files window
// that shows a place belongs to it rather than to Files, so the place has the window's dot and its click goes back
// to it; Files says which window shows what through the file manager interface it publishes on the session bus.

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Shell from 'gi://Shell';

import {gettext as _} from 'resource:///org/gnome/shell/extensions/extension.js';
import {EventEmitter} from 'resource:///org/gnome/shell/misc/signals.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as ShellMountOperation from 'resource:///org/gnome/shell/ui/shellMountOperation.js';

const FILES = 'org.gnome.Nautilus.desktop';
const FILES_BUS = 'org.gnome.Nautilus';
const TRASH = 'trash:///';
// The trash is looked at again this long after it changed, so that emptying it is one look and not thousands
const TRASH_SETTLE = 1000;

// Whether uri is the place itself or somewhere inside it
const inside = (uri, root) => uri === root || uri.startsWith(root.endsWith('/') ? root : `${root}/`);

export class Places extends EventEmitter {
    start() {
        this._cancellable = new Gio.Cancellable();
        this._mounts = [];
        this._locations = {};
        this.trash = {
            uri: TRASH,
            name: _('Trash'),
            gicon: Gio.ThemedIcon.new('user-trash'),
            fallback: 'user-trash',
            full: false,
        };
        this._watchTrash();

        this._volumes = Gio.VolumeMonitor.get();
        this._volumes.connectObject(
            'mount-added', (monitor, mount) => this._addMount(mount),
            'mount-removed', (monitor, mount) => this._removeMount(mount),
            'mount-changed', (monitor, mount) => this._changeMount(mount),
            this);
        for (const mount of this._volumes.get_mounts())
            this._addMount(mount);

        // Only while Files runs; asking does not start it
        Gio.DBusProxy.new_for_bus(Gio.BusType.SESSION, Gio.DBusProxyFlags.DO_NOT_AUTO_START, null,
            'org.freedesktop.FileManager1', '/org/freedesktop/FileManager1', 'org.freedesktop.FileManager1',
            this._cancellable, (object, result) => {
                try {
                    this._fileManager = Gio.DBusProxy.new_for_bus_finish(result);
                } catch (e) {
                    if (!e.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                        console.warn(`Amethystora UI: the dock cannot ask Files what it shows: ${e.message}`);
                    return;
                }
                this._fileManager.connectObject('g-properties-changed', () => this._readLocations(), this);
                this._readLocations();
            });

        const apps = Shell.AppSystem.get_default();
        apps.connectObject('installed-changed', () => this._watchFiles(), this);
        this._watchFiles();
    }

    stop() {
        this._cancellable?.cancel();
        this._cancellable = null;
        this._volumes?.disconnectObject(this);
        this._volumes = null;
        this._fileManager?.disconnectObject(this);
        this._fileManager = null;
        this._files?.disconnectObject(this);
        this._files = null;
        Shell.AppSystem.get_default().disconnectObject(this);
        this._trashMonitor?.cancel();
        this._trashMonitor = null;
        if (this._trashId)
            GLib.source_remove(this._trashId);
        this._trashId = 0;
        this._mounts = [];
        this._locations = {};
    }

    // Drives in the order they appeared, then the trash
    list() {
        return [...this._mounts, this.trash];
    }

    // The place a window shows, or null
    owner(window) {
        const uris = this._locations[window.get_gtk_window_object_path?.() ?? ''];
        if (!uris)
            return null;
        return this.list().find(place => uris.some(uri => inside(uri, place.uri))) ?? null;
    }

    windowsOf(place) {
        const windows = this._files?.get_windows() ?? [];
        return windows.filter(window => !window.skip_taskbar && this.owner(window) === place);
    }

    // In the program that opens it, which finds a Files window already showing it
    open(place) {
        try {
            Gio.AppInfo.launch_default_for_uri(place.uri, global.create_app_launch_context(0, -1));
        } catch (e) {
            Main.notifyError(_('%s could not be opened').format(place.name), e.message);
        }
    }

    // A new Files window, even when one shows the place already
    openNew(place) {
        const app = Shell.AppSystem.get_default().lookup_app(FILES);
        const platform = {};
        if (app) {
            const context = global.create_app_launch_context(0, -1);
            const token = context.get_startup_notify_id(app.get_app_info(), []);
            if (token)
                platform['activation-token'] = new GLib.Variant('s', token);
        }
        Gio.DBus.session.call(FILES_BUS, '/org/gnome/Nautilus', 'org.gtk.Application', 'Open',
            new GLib.Variant('(assa{sv})', [[place.uri], 'new-window', platform]), null,
            Gio.DBusCallFlags.NONE, -1, null, (connection, result) => {
                try {
                    connection.call_finish(result);
                } catch (e) {
                    Main.notifyError(_('%s could not be opened').format(place.name), e.message);
                }
            });
    }

    // What the place's menu offers beside its windows: [{label, busy, run()}]
    actions(place) {
        if (place === this.trash)
            return place.full ? [{label: _('Empty trash'), busy: false, run: () => this._emptyTrash()}] : [];
        const actions = [];
        if (place.mount.can_unmount())
            actions.push({label: _('Unmount'), busy: Boolean(place.busy), run: () => this._unmount(place, false)});
        if (place.mount.can_eject())
            actions.push({label: _('Eject'), busy: Boolean(place.busy), run: () => this._unmount(place, true)});
        return actions;
    }

    _watchFiles() {
        const files = Shell.AppSystem.get_default().lookup_app(FILES);
        if (files === this._files)
            return;
        this._files?.disconnectObject(this);
        this._files = files;
        this._files?.connectObject('windows-changed', () => this.emit('windows-changed'), this);
    }

    _readLocations() {
        const value = this._fileManager?.get_cached_property('OpenWindowsWithLocations');
        try {
            this._locations = value?.deepUnpack() ?? {};
        } catch {
            this._locations = {};
        }
        this.emit('windows-changed');
    }

    _watchTrash() {
        try {
            this._trashMonitor = Gio.File.new_for_uri(TRASH).monitor_directory(Gio.FileMonitorFlags.NONE,
                this._cancellable);
            this._trashMonitor.connect('changed', () => this._queueTrash());
        } catch (e) {
            // No trash to watch here (no GVfs): its plain icon stays
            console.warn(`Amethystora UI: the trash cannot be watched: ${e.message}`);
        }
        this._readTrash();
    }

    _queueTrash() {
        if (this._trashId)
            return;
        this._trashId = GLib.timeout_add(GLib.PRIORITY_LOW, TRASH_SETTLE, () => {
            this._trashId = 0;
            this._readTrash();
            return GLib.SOURCE_REMOVE;
        });
    }

    _readTrash() {
        Gio.File.new_for_uri(TRASH).query_info_async('standard::icon,trash::item-count',
            Gio.FileQueryInfoFlags.NONE, GLib.PRIORITY_LOW, this._cancellable, (file, result) => {
                let info;
                try {
                    info = file.query_info_finish(result);
                } catch {
                    return;
                }
                this.trash.full = info.get_attribute_uint32('trash::item-count') > 0;
                this.trash.gicon = info.get_icon() ??
                    Gio.ThemedIcon.new(this.trash.full ? 'user-trash-full' : 'user-trash');
                this.emit('place-changed', this.trash);
            });
    }

    // A drive the person can take away: not a network share, not one hidden behind another, not the system's own
    _wanted(mount) {
        return !mount.is_shadowed() && (mount.can_unmount() || mount.can_eject()) && mount.get_root().is_native();
    }

    _addMount(mount) {
        if (this._mounts.some(place => place.mount === mount) || !this._wanted(mount))
            return;
        const place = {mount, fallback: 'media-removable'};
        this._describe(place);
        this._mounts.push(place);
        this.emit('places-changed');
    }

    _removeMount(mount) {
        const count = this._mounts.length;
        this._mounts = this._mounts.filter(place => place.mount !== mount);
        if (this._mounts.length !== count)
            this.emit('places-changed');
    }

    _changeMount(mount) {
        const place = this._mounts.find(p => p.mount === mount);
        if (!place) {
            this._addMount(mount);
            return;
        }
        if (!this._wanted(mount)) {
            this._removeMount(mount);
            return;
        }
        this._describe(place);
        this.emit('place-changed', place);
    }

    _describe(place) {
        place.uri = place.mount.get_root().get_uri();
        place.name = place.mount.get_name();
        place.gicon = place.mount.get_icon() ?? Gio.ThemedIcon.new('media-removable');
    }

    _emptyTrash() {
        // Files asks first, in its own dialog
        const platform = {timestamp: new GLib.Variant('u', global.get_current_time())};
        Gio.DBus.session.call(FILES_BUS, '/org/gnome/Nautilus/FileOperations2', 'org.gnome.Nautilus.FileOperations2',
            'EmptyTrash', new GLib.Variant('(ba{sv})', [true, platform]), null, Gio.DBusCallFlags.NONE, -1, null,
            (connection, result) => {
                try {
                    connection.call_finish(result);
                } catch (e) {
                    Main.notifyError(_('The trash could not be emptied'), e.message);
                }
            });
    }

    // Forced, as the drive is going anyway; GNOME's own dialog says which programs still use it
    _unmount(place, eject) {
        if (place.busy)
            return;
        place.busy = true;
        const {mount} = place;
        const operation = new ShellMountOperation.ShellMountOperation(mount);
        const done = (object, result) => {
            place.busy = false;
            operation.close();
            try {
                if (eject)
                    mount.eject_with_operation_finish(result);
                else
                    mount.unmount_with_operation_finish(result);
            } catch (e) {
                if (!e.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.FAILED_HANDLED)) {
                    Main.notifyError(eject
                        ? _('%s could not be ejected').format(place.name)
                        : _('%s could not be unmounted').format(place.name), e.message);
                }
            }
        };
        if (eject)
            mount.eject_with_operation(Gio.MountUnmountFlags.FORCE, operation.mountOp, null, done);
        else
            mount.unmount_with_operation(Gio.MountUnmountFlags.FORCE, operation.mountOp, null, done);
    }
}
