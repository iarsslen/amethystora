// The theme's colours in the shell. amethystora-theme renders each /usr/share/amethystora/themed/shell-<module>.css.tpl
// from the palette into the current theme, and this loads every one of them over the modules' own stylesheets, which
// hold what never changes with the theme. They are loaded again whenever the theme changes. A theme can hand-write any
// of them.

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';

const CURRENT = GLib.build_filenamev([GLib.get_user_config_dir(), 'amethystora', 'current']);
const THEME_DIR = GLib.build_filenamev([CURRENT, 'theme']);
const STYLESHEET = /^shell-[a-z]+\.css$/;
// Milliseconds for a theme switch (a folder taken away, another moved in, the name written) to settle
const SETTLE = 300;
// What a theme switch touches in the current folder: the theme's own folder and the file that names it. A new
// wallpaper touches others (the `background` link, `backgrounds/`), and none of those changes a stylesheet.
const SWITCH = ['theme', 'theme.name'];

export class Theme {
    enable() {
        this._files = [];
        this._load();
        try {
            this._monitor = Gio.File.new_for_path(CURRENT).monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, null);
            // A move names both of its ends (the folder it was built in, then the one it became)
            this._monitor.connect('changed', (monitor, file, other) => {
                if ([file, other].some(each => SWITCH.includes(each?.get_basename())))
                    this._queue();
            });
        } catch (e) {
            // Before the first theme there is no folder to watch: the next login loads what the theme set
            console.warn(`Amethystora UI: ${CURRENT} cannot be watched: ${e.message}`);
        }
    }

    disable() {
        this._monitor?.cancel();
        this._monitor = null;
        if (this._timeout)
            GLib.source_remove(this._timeout);
        this._timeout = 0;
        this._unload();
    }

    _queue() {
        if (this._timeout)
            GLib.source_remove(this._timeout);
        this._timeout = GLib.timeout_add(GLib.PRIORITY_DEFAULT, SETTLE, () => {
            this._timeout = 0;
            this._load();
            return GLib.SOURCE_REMOVE;
        });
    }

    // The shell keeps an extension's stylesheets when it loads its own theme again, so the theme asked here is
    // always the one in use
    _unload() {
        const theme = St.ThemeContext.get_for_stage(global.stage).get_theme();
        for (const file of this._files ?? [])
            theme.unload_stylesheet(file);
        this._files = [];
    }

    _load() {
        this._unload();
        const names = [];
        try {
            const children = Gio.File.new_for_path(THEME_DIR).enumerate_children('standard::name',
                Gio.FileQueryInfoFlags.NONE, null);
            for (const info of children)
                names.push(info.get_name());
        } catch {
            // No theme applied yet: the modules' own stylesheets stand alone
            return;
        }
        const theme = St.ThemeContext.get_for_stage(global.stage).get_theme();
        for (const name of names.filter(n => STYLESHEET.test(n)).sort()) {
            const file = Gio.File.new_for_path(GLib.build_filenamev([THEME_DIR, name]));
            try {
                theme.load_stylesheet(file);
                this._files.push(file);
            } catch (e) {
                console.warn(`Amethystora UI: the theme's ${name} was not loaded: ${e.message}`);
            }
        }
    }
}
