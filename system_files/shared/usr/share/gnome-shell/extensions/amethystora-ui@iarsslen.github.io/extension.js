// Amethystora's own desktop, in place of the third-party extensions the image used to ship. Each part is a module
// in modules/, written for this image from what those extensions did with the image's settings and nothing more
// (plans/PLAN-amethystora-ui.md). Every module is started on its own, so one that fails leaves the others running
// and says why in the journal. A module's stylesheet, stylesheets/<module>.css, is loaded while it runs; the
// colours that follow the theme are in /usr/share/amethystora/themed/shell-<module>.css.tpl (modules/theme.js).

import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

import {Theme} from './modules/theme.js';
import {Tweaks} from './modules/tweaks.js';
import {Workspaces} from './modules/workspaces.js';
import {Meters} from './modules/meters.js';

// In the order they start, by the name of their stylesheet; they stop in the opposite order. The glass comes after
// the dock and the panel's modules, whose actors it draws behind.
const MODULES = [
    ['theme', Theme],
    ['tweaks', Tweaks],
    ['workspaces', Workspaces],
    ['meters', Meters],
];

export default class AmethystoraUI extends Extension {
    enable() {
        // The running modules by name, for a module that needs another's actors (the glass, the dock's)
        this.modules = new Map();
        for (const [name, Module] of MODULES) {
            const module = new Module(this);
            try {
                module.enable();
                this.modules.set(name, module);
                this._loadStylesheet(name, module);
            } catch (e) {
                console.error(`Amethystora UI: the ${name} module did not start: ${e.message}\n${e.stack}`);
                // A module stops cleanly from wherever it got to
                try {
                    module.disable();
                } catch {}
            }
        }
    }

    disable() {
        for (const [name, module] of [...this.modules].reverse()) {
            try {
                module.disable();
            } catch (e) {
                console.error(`Amethystora UI: the ${name} module did not stop cleanly: ${e.message}`);
            }
            if (module.stylesheet)
                St.ThemeContext.get_for_stage(global.stage).get_theme().unload_stylesheet(module.stylesheet);
        }
        this.modules = null;
    }

    _loadStylesheet(name, module) {
        const file = this.dir.get_child('stylesheets').get_child(`${name}.css`);
        if (!file.query_exists(null))
            return;
        try {
            St.ThemeContext.get_for_stage(global.stage).get_theme().load_stylesheet(file);
            module.stylesheet = file;
        } catch (e) {
            console.error(`Amethystora UI: stylesheets/${name}.css: ${e.message}`);
        }
    }
}

