// The glass: the shell drawn on frosted panes of the wallpaper. The top bar is a clear strip of it until a window
// touches the bar; the dock, every menu and popup, the dialogs and the application windows that are not being used
// stand on panes of thick, milky glass with a lens along their edges; the overview pushes the wallpaper far back
// behind a darker frost, and app folders open over a live blur of the app grid. The glass is a still picture of the
// desktop cut to each surface, never a view of the windows behind it: blurred once per screen, it costs nothing while
// nothing changes. Not on the lock screen, where GNOME's own blur stays.
//
// The frosted pictures are in glass/frost.js, the effect that draws a pane under a surface in glass/effect.js with
// its shader in glass/lens.glsl; the parts that find GNOME's surfaces are glass/popups.js, glass/topbar.js,
// glass/windows.js and glass/backdrops.js.

import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {Backdrops} from './glass/backdrops.js';
import {GlassEffect} from './glass/effect.js';
import {Frost} from './glass/frost.js';
import {Popups} from './glass/popups.js';
import {Shader} from './glass/shader.js';
import {TopBar} from './glass/topbar.js';
import {Windows} from './glass/windows.js';

const EFFECT = 'amethystora-glass';
const LIGHT = 'amethystora-glass-light';

export class Glass {
    constructor(ext) {
        this._ext = ext;
    }

    enable() {
        this._surfaces = new Map();
        this._moduleSurfaces = new Set();
        this._wrapped = [];
        this._parts = [];

        const file = this._ext.dir.get_child('modules').get_child('glass').get_child('lens.glsl');
        const [, bytes] = file.load_contents(null);
        this.shader = new Shader(new TextDecoder().decode(bytes), 'cogl_color_out = glass_color();', 2);
        this.frost = new Frost();

        this.light = Main.getStyleVariant() === 'light';
        St.Settings.get().connectObject('notify::color-scheme', () => this._syncScheme(), this);

        // The windows first: the top bar and the workspace slide ask them
        this.windows = new Windows(this);
        this._topBar = new TopBar(this);
        for (const part of [this.windows, new Popups(this), this._topBar, new Backdrops(this)]) {
            this._parts.push(part);
            part.enable();
        }
        this._running = true;
        // A new desktop style, or new buttons on a bar whose buttons each have glass. The menus, banners, dialogs
        // and the dock take their corners from the stylesheet as they are drawn, and need nothing.
        this.style?.onChange(() => {
            if (!this._running)
                return;
            this.windows.restyle();
            this._topBar.restyle();
        });
        this.surfacesChanged();
    }

    // The desktop style module, when it runs
    get style() {
        return this._ext.modules.get('style') ?? null;
    }

    // The corners of a window's pane: the desktop style's, which its GTK stylesheet gives the windows too
    get windowRadius() {
        return this.style?.look.window ?? 16;
    }

    disable() {
        this._running = false;
        St.Settings.get().disconnectObject(this);
        for (const part of [...this._parts ?? []].reverse())
            part.disable();
        this._parts = [];
        this.windows = null;
        this._topBar = null;
        // GNOME's methods back as they were, the last wrapped first
        for (const [proto, name, descriptor] of [...this._wrapped ?? []].reverse()) {
            if (descriptor)
                Object.defineProperty(proto, name, descriptor);
            else
                delete proto[name];
        }
        this._wrapped = [];
        for (const actor of [...this._surfaces?.keys() ?? []])
            this.detach(actor);
        this._surfaces = null;
        this._moduleSurfaces = null;
        this.frost?.destroy();
        this.frost = null;
        this.shader?.destroy();
        this.shader = null;
    }

    // The other modules' own surfaces (the dock's pill): asked for again whenever one of them rebuilds its actors.
    // The frame stops the glass before the dock, which still calls this as it goes.
    surfacesChanged() {
        if (!this._running)
            return;
        const listed = new Set();
        for (const module of this._ext.modules.values()) {
            for (const {actor, material, radius} of module.glassSurfaces?.() ?? []) {
                listed.add(actor);
                this.attach(actor, {material, radius});
            }
        }
        for (const actor of this._moduleSurfaces) {
            if (!listed.has(actor))
                this.detach(actor);
        }
        this._moduleSurfaces = listed;
    }

    // Gives an actor its pane, or a new look for the pane it has. classes are style classes it carries while it has
    // one; with scheme, it also carries the light scheme's class and its shadow follows the scheme.
    attach(actor, look, {classes = [], scheme = false} = {}) {
        let surface = this._surfaces.get(actor);
        if (surface) {
            surface.effect.update(look);
            return surface.effect;
        }
        const effect = new GlassEffect(this, look);
        actor.add_effect_with_name(EFFECT, effect);
        surface = {effect, classes, scheme};
        this._surfaces.set(actor, surface);
        for (const name of classes)
            actor.add_style_class_name(name);
        if (scheme)
            this._schemeOf(actor, surface);
        actor.connectObject('destroy', () => {
            effect.forget();
            this._surfaces?.delete(actor);
        }, this);
        return effect;
    }

    detach(actor) {
        const surface = this._surfaces?.get(actor);
        if (!surface)
            return;
        this._surfaces.delete(actor);
        actor.disconnectObject(this);
        actor.remove_effect(surface.effect);
        surface.effect.forget();
        // Only widgets were given classes: a window's actor is not one
        for (const name of surface.scheme ? [...surface.classes, LIGHT] : surface.classes)
            actor.remove_style_class_name(name);
    }

    // A GNOME method with the glass's work around it: around(original, instance, args) is called in its place, and
    // disable() puts the method back
    wrap(proto, name, around) {
        const original = proto[name];
        this._wrapped.push([proto, name, Object.getOwnPropertyDescriptor(proto, name)]);
        proto[name] = function (...args) {
            return around(original, this, args);
        };
    }

    has(actor) {
        return this._surfaces?.has(actor) ?? false;
    }

    effectOf(actor) {
        return this._surfaces?.get(actor)?.effect ?? null;
    }

    // The soft shadow under a popup, as the scheme has it
    get shadow() {
        return this.light ? {alpha: 0.08, blur: 22, offset: 8} : {alpha: 0.16, blur: 24, offset: 8};
    }

    _schemeOf(actor, surface) {
        if (this.light)
            actor.add_style_class_name(LIGHT);
        else
            actor.remove_style_class_name(LIGHT);
        if (surface.effect.look.shadow)
            surface.effect.update({shadow: this.shadow});
    }

    _syncScheme() {
        const light = Main.getStyleVariant() === 'light';
        if (light === this.light)
            return;
        this.light = light;
        for (const [actor, surface] of this._surfaces) {
            if (surface.scheme)
                this._schemeOf(actor, surface);
        }
    }
}
