// The frosted pictures the glass is cut from: for each screen and each strength of frost, the desktop's wallpaper as
// that screen shows it, blurred once and kept in a small texture that every surface on the screen shares. Nothing is
// blurred again until the wallpaper or the screens change.
//
// A picture is made by an actor that is never shown: the screen's wallpaper, with GNOME's blur on it and, around
// that, an effect that renders the result into the texture. A one-pixel clone of that actor in the corner of its
// screen is what gets it painted: Clutter redraws a clone whenever the actor it copies changes, so the wallpaper
// changing (or fading into another) is all it takes, and the clone itself draws nothing.

import Clutter from 'gi://Clutter';
import Cogl from 'gi://Cogl';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Graphene from 'gi://Graphene';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as Background from 'resource:///org/gnome/shell/ui/background.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

// The strengths of frost: the blur's radius in pixels (times the screen's scale), the brightness after it, and how
// many times smaller than the screen the texture is across. The glass is drawn from the first, the overview's
// backdrop from the second; the third is the wallpaper itself, which a pane fading in or out is mixed towards. Blurred
// this much, nothing is lost by a quarter of the screen; the sharp one is kept at half, and seen only faintly.
export const RECIPES = {
    glass: {radius: 48, brightness: 1.0, shrink: 4},
    frost: {radius: 64, brightness: 0.55, shrink: 4},
    clear: {radius: 0, brightness: 1.0, shrink: 2},
};

// Renders the actor it is on, blurred by the effect after it, into the picture's texture whenever the actor has
// changed, and draws nothing on the screen
const Capture = GObject.registerClass(
class AmethystoraGlassCapture extends Clutter.Effect {
    _init(picture) {
        super._init();
        this._picture = picture;
    }

    vfunc_paint_node(node, paintContext, flags) {
        const picture = this._picture;
        if (picture.ready && !(flags & Clutter.EffectPaintFlags.ACTOR_DIRTY))
            return;
        const framebuffer = picture.framebuffer(paintContext.get_framebuffer().get_context());
        if (!framebuffer)
            return;

        const actor = this.get_actor();
        const layer = Clutter.LayerNode.new_to_framebuffer(framebuffer, picture.blank);
        node.add_child(layer);
        const scale = new Graphene.Matrix();
        scale.init_scale(picture.width / actor.width, picture.height / actor.height, 1);
        const transform = new Clutter.TransformNode(scale);
        layer.add_child(transform);
        transform.add_child(new Clutter.ActorNode(actor, 255));
        picture.rendered();
    }
});

class Picture {
    constructor(frost, holder, monitor, name) {
        const recipe = RECIPES[name];
        this.recipe = name;
        this._frost = frost;
        this.monitor = monitor;
        this.consumers = new Set();
        this.texture = null;
        this.ready = false;
        this.width = Math.max(1, Math.ceil(monitor.width / recipe.shrink));
        this.height = Math.max(1, Math.ceil(monitor.height / recipe.shrink));

        const scale = St.ThemeContext.get_for_stage(global.stage).scale_factor;
        this._source = new Clutter.Actor({visible: false, width: monitor.width, height: monitor.height});
        // Backgrounds of its own rather than a copy of the desktop's: the window manager leaves out the parts of
        // the desktop's that windows cover, which would be holes in the frost. The wallpaper itself is GNOME's
        // shared copy, and a new one is put in as GNOME puts it on the desktop.
        this._backgrounds = new Background.BackgroundManager({
            container: this._source,
            monitorIndex: monitor.index,
            controlPosition: false,
        });
        this._source.add_effect(new Capture(this));
        if (recipe.radius > 0) {
            this._source.add_effect(new Shell.BlurEffect({
                mode: Shell.BlurMode.ACTOR,
                radius: Math.round(recipe.radius * scale),
                brightness: recipe.brightness,
            }));
        }
        holder.add_child(this._source);

        this._driver = new Clutter.Clone({
            source: this._source,
            x: monitor.x + monitor.width - 1,
            y: monitor.y + monitor.height - 1,
            width: 1,
            height: 1,
        });
        holder.add_child(this._driver);
    }

    // The texture and the render target over it, made on the first paint, when the GPU is at hand. Should the GPU
    // refuse them, that screen goes without glass rather than asking again on every frame.
    framebuffer(context) {
        if (this._framebuffer || this._refused)
            return this._framebuffer ?? null;
        try {
            const texture = Cogl.Texture2D.new_with_size(context, this.width, this.height);
            texture.set_premultiplied(true);
            const framebuffer = Cogl.Offscreen.new_with_texture(texture);
            framebuffer.allocate();
            framebuffer.orthographic(0, 0, this.width, this.height, -1, 1);
            this.blank = Cogl.Pipeline.new(context);
            this.texture = texture;
            this._framebuffer = framebuffer;
        } catch (e) {
            console.error(`Amethystora UI: the glass has no picture for a screen: ${e.message}`);
            this._refused = true;
            return null;
        }
        return this._framebuffer;
    }

    // Called from the paint that drew a new picture: the surfaces showing it are drawn again before the next frame
    rendered() {
        this.ready = true;
        this._frost.redrawSoon(this);
    }

    // Drawn again from scratch, as after the GPU lost its memory
    refresh() {
        this.ready = false;
        this._source.queue_redraw();
    }

    destroy() {
        this._driver.destroy();
        this._backgrounds.destroy();
        this._source.destroy();
        this.consumers.clear();
        this.texture = null;
        this._framebuffer = null;
        this.blank = null;
    }
}

export class Frost {
    constructor() {
        this._pictures = new Map();
        this._queued = new Set();
        this._laterId = 0;
        // Under every other actor of the stage, so that a new picture is ready before anything is drawn from it
        this._holder = new Clutter.Actor({name: 'amethystoraGlassPictures'});
        global.stage.insert_child_below(this._holder, Main.layoutManager.uiGroup);
        Main.layoutManager.connectObject('monitors-changed', () => this._rebuild(), this);
        St.ThemeContext.get_for_stage(global.stage).connectObject('notify::scale-factor', () => this._rebuild(), this);
        // GNOME 50 says when the GPU lost what it held, and the pictures are drawn again; GNOME 51 has no such signal
        if (GObject.signal_lookup('gl-video-memory-purged', global.stage.constructor.$gtype)) {
            global.stage.connectObject('gl-video-memory-purged', () => {
                for (const picture of this._pictures.values())
                    picture.refresh();
            }, this);
        }
        this._build();
    }

    // Every picture is made up front, so that none is made during a paint and the overview never opens on a
    // backdrop still to come
    _build() {
        this._byRecipe = null;
        for (const monitor of Main.layoutManager.monitors) {
            for (const name of Object.keys(RECIPES))
                this._pictures.set(`${monitor.index}:${name}`, new Picture(this, this._holder, monitor, name));
        }
    }

    destroy() {
        Main.layoutManager.disconnectObject(this);
        St.ThemeContext.get_for_stage(global.stage).disconnectObject(this);
        global.stage.disconnectObject(this);
        if (this._laterId)
            global.compositor.get_laters().remove(this._laterId);
        this._laterId = 0;
        this._queued.clear();
        for (const picture of this._pictures.values())
            picture.destroy();
        this._pictures.clear();
        this._byRecipe = null;
        this._holder.destroy();
        this._holder = null;
    }

    // The picture of a screen (an index into Main.layoutManager.monitors) for a recipe
    picture(index, recipe) {
        return this._pictures.get(`${index}:${recipe}`) ?? null;
    }

    // The pictures of every screen for a recipe. Asked for on every paint of every pane, so the lists are made once
    // with the pictures rather than each time.
    pictures(recipe) {
        if (!this._byRecipe) {
            this._byRecipe = new Map();
            for (const picture of this._pictures.values()) {
                if (!this._byRecipe.has(picture.recipe))
                    this._byRecipe.set(picture.recipe, []);
                this._byRecipe.get(picture.recipe).push(picture);
            }
        }
        return this._byRecipe.get(recipe) ?? [];
    }

    // Surfaces that drew from a picture are drawn again once it changes. Queued from inside a paint, so it is done
    // just before the next frame.
    redrawSoon(picture) {
        this._queued.add(picture);
        if (this._laterId)
            return;
        this._laterId = global.compositor.get_laters().add(Meta.LaterType.BEFORE_REDRAW, () => {
            this._laterId = 0;
            for (const queued of this._queued) {
                for (const consumer of queued.consumers)
                    consumer.get_actor()?.queue_redraw();
            }
            this._queued.clear();
            return GLib.SOURCE_REMOVE;
        });
    }

    // New screens, or a new scale: every picture is made again, and every surface finds its own on its next paint
    _rebuild() {
        const consumers = new Set();
        for (const picture of this._pictures.values()) {
            for (const consumer of picture.consumers)
                consumers.add(consumer);
            picture.destroy();
        }
        this._pictures.clear();
        this._build();
        for (const consumer of consumers)
            consumer.get_actor()?.queue_redraw();
    }
}
