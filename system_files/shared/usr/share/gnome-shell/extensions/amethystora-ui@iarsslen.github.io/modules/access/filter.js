// Colour filters: the whole screen drawn through one colour matrix (matrices.js), for an eye that mixes up reds and
// greens or blues and yellows, or in grey. Each screen is drawn as always, then what it holds is copied
// into a texture of that screen's own pixels and drawn back over itself through a small fragment shader (a snippet on
// the texture's Cogl pipeline): one copy and one pass of each screen per frame, while a filter is on; nothing at all
// while none is. The texture is the screen's own size and scale, so nothing is resampled; the pointer is not filtered,
// since Mutter draws it apart from the stage.
//
// Only what is drawn for a screen is filtered. A paint of the stage that is no screen's (a screenshot, the screenshot
// UI's picture, a colour picker's reading, a recording of an area) has the apps' own colours, so that a picture someone
// is sent looks right; a recording of a whole screen is that screen, filtered. While on, fullscreen windows are
// composited like the rest, else a game would skip the filter.
//
// A tile in quick settings while a filter is chosen: its switch draws the filter or not without forgetting it, its
// menu picks the filter and how strong it is.

import Clutter from 'gi://Clutter';
import Cogl from 'gi://Cogl';
import GObject from 'gi://GObject';

import {gettext as _} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {QuickMenuToggle, SystemIndicator} from 'resource:///org/gnome/shell/ui/quickSettings.js';

import {FILTERS, filterMatrix} from './matrices.js';

export const EFFECT_NAME = 'amethystora-access-filter';
// The strengths the tile offers, as the board's chips
const STRENGTHS = [50, 75, 100];
// A screen too large for the filter is said once a session
let toldTooLarge = false;

// sRGB to linear light and back, the matrix in between, on the colour with its alpha taken out and put back
const DECLARATIONS = `
uniform vec3 amethystora_row0;
uniform vec3 amethystora_row1;
uniform vec3 amethystora_row2;
vec3 amethystora_linear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}
vec3 amethystora_encoded(vec3 c) {
    return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}`;
const CODE = `
float amethystora_a = cogl_color_out.a;
vec3 amethystora_c = amethystora_a > 0.0 ? cogl_color_out.rgb / amethystora_a : vec3(0.0);
amethystora_c = amethystora_linear(clamp(amethystora_c, 0.0, 1.0));
amethystora_c = clamp(vec3(dot(amethystora_row0, amethystora_c), dot(amethystora_row1, amethystora_c),
    dot(amethystora_row2, amethystora_c)), 0.0, 1.0);
cogl_color_out = vec4(amethystora_encoded(amethystora_c) * amethystora_a, amethystora_a);`;

export const FilterEffect = GObject.registerClass(
class AmethystoraAccessFilterEffect extends Clutter.Effect {
    _init(failed) {
        super._init();
        this._matrix = filterMatrix('none', 0);
        // Per screen: its texture, the framebuffer drawn into it and the pipeline that draws it back
        this._views = new Map();
        this._failed = failed;
        this.failed = false;
    }

    setMatrix(matrix) {
        this._matrix = matrix;
        for (const target of this._views.values())
            this._setUniforms(target.pipeline);
        this.get_actor()?.queue_redraw();
    }

    // The screens changed: their textures are made again as they are drawn
    release() {
        this._views.clear();
    }

    _setUniforms(pipeline) {
        for (let row = 0; row < 3; row++) {
            const location = pipeline.get_uniform_location(`amethystora_row${row}`);
            if (location >= 0)
                pipeline.set_uniform_float(location, 3, 1, this._matrix.slice(row * 3, row * 3 + 3));
        }
    }

    // The texture for a screen, the size of the framebuffer the screen is drawn into
    _target(view, framebuffer) {
        const width = framebuffer.get_width();
        const height = framebuffer.get_height();
        const known = this._views.get(view);
        if (known?.width === width && known.height === height)
            return known;
        this._views.delete(view);
        const context = framebuffer.get_context();
        const texture = Cogl.Texture2D.new_with_size(context, width, height);
        const offscreen = Cogl.Offscreen.new_with_texture(texture);
        // Throws where the texture cannot be had (larger than the GPU takes)
        offscreen.allocate();
        const pipeline = Cogl.Pipeline.new(context);
        pipeline.set_layer_texture(0, texture);
        // Pixel for pixel: the texture is the screen's own size
        pipeline.set_layer_filters(0, Cogl.PipelineFilter.NEAREST, Cogl.PipelineFilter.NEAREST);
        pipeline.add_snippet(Cogl.Snippet.new(Cogl.SnippetHook.FRAGMENT, DECLARATIONS, CODE));
        this._setUniforms(pipeline);
        const target = {width, height, offscreen, pipeline};
        this._views.set(view, target);
        return target;
    }

    vfunc_paint_node(node, paintContext, _flags) {
        const actor = this.get_actor();
        const framebuffer = paintContext.get_framebuffer();
        // The screen this paint is for (GJS has no get_stage_view): the view whose framebuffer it draws into
        let view = global.stage.peek_stage_views().find(v => v.get_framebuffer() === framebuffer) ?? null;
        // For the suites only: a whole-stage paint (a screenshot) drawn as the screen shows it
        if (!view && this.everyPaintForTest)
            view = framebuffer;
        let target = null;
        // A paint for no screen (a screenshot) or inside a clone is the apps' own colours
        if (view && framebuffer && !actor.is_in_clone_paint() && !this.failed) {
            try {
                target = this._target(view, framebuffer);
            } catch (e) {
                this.failed = true;
                this._failed?.(e);
            }
        }
        if (!target) {
            node.add_child(new Clutter.ActorNode(actor, -1));
            return;
        }
        // The group is drawn into the screen as always (culled to what is redrawn), then what the screen now holds is
        // copied into the texture and drawn back over it through the filter. Only the part being redrawn reaches the
        // screen, so a part not redrawn is never filtered twice.
        node.add_child(new Clutter.ActorNode(actor, -1));
        // The whole screen is copied; drawing back reaches only the part being redrawn, as everything drawn does. (The
        // redraw clip is not read: GJS frees the region it is handed, which ends the shell.)
        const layer = Clutter.LayerNode.new_to_framebuffer(target.offscreen, target.pipeline);
        const blit = Clutter.BlitNode.new(framebuffer);
        blit.add_blit_rectangle(0, 0, 0, 0, target.width, target.height);
        layer.add_child(blit);
        // Where the framebuffer lies on the stage, from how the stage is mapped onto it
        const [x, y, width] = framebuffer.get_viewport4fv();
        const scale = width / global.stage.width;
        layer.add_texture_rectangle(new Clutter.ActorBox({
            x1: -x / scale, y1: -y / scale, x2: (target.width - x) / scale, y2: (target.height - y) / scale,
        }), 0, 0, 1, 1);
        node.add_child(layer);
    }

    get bytes() {
        return [...this._views.values()].reduce((sum, t) => sum + t.width * t.height * 4, 0);
    }
});

const FilterTile = GObject.registerClass(
class AmethystoraAccessFilterTile extends QuickMenuToggle {
    _init(filter) {
        super._init({title: _('Colour filter'), iconName: 'color-select-symbolic', toggleMode: true});
        this._amethystoraQuickId = 'colour-filter';
        this._filter = filter;
        this.menu.setHeader('color-select-symbolic', _('Colour filter'));

        this._kinds = new Map();
        for (const id of FILTERS) {
            const item = new PopupMenu.PopupMenuItem(filterName(id));
            item.connect('activate', () => this._filter.choose(id));
            this.menu.addMenuItem(item);
            this._kinds.set(id, item);
        }
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem(_('Strength')));
        this._strengths = new Map();
        for (const value of STRENGTHS) {
            const item = new PopupMenu.PopupMenuItem(strengthName(value));
            item.connect('activate', () => this._filter.setStrength(value));
            this.menu.addMenuItem(item);
            this._strengths.set(value, item);
        }
        this.connect('clicked', () => this._filter.setOn(this.checked));
    }

    sync(filter, on, strength) {
        this.checked = on;
        this.subtitle = filterName(filter);
        for (const [id, item] of this._kinds)
            item.setOrnament(id === filter ? PopupMenu.Ornament.CHECK : PopupMenu.Ornament.NONE);
        for (const [value, item] of this._strengths)
            item.setOrnament(value === strength ? PopupMenu.Ornament.CHECK : PopupMenu.Ornament.NONE);
    }
});

export function filterName(id) {
    switch (id) {
    case 'protan':
        return _('Red (protan)');
    case 'deutan':
        return _('Green (deutan)');
    case 'tritan':
        return _('Blue-yellow');
    case 'grey':
        return _('Grey');
    default:
        return _('Off');
    }
}

function strengthName(value) {
    switch (value) {
    case 50:
        return _('Half');
    case 75:
        return _('¾');
    default:
        return _('Full');
    }
}

export class Filter {
    constructor(settings) {
        this._settings = settings;
        this._effect = null;
        this._indicator = null;
        this._tile = null;
        this._unredirected = false;
    }

    enable() {
        this._settings.connectObject(
            'changed::filter', () => this.sync(),
            'changed::filter-on', () => this.sync(),
            'changed::filter-strength', () => this.sync(),
            this);
        this.sync();
    }

    disable() {
        this._settings?.disconnectObject(this);
        Main.layoutManager.disconnectObject(this);
        this._setEffect(null);
        this._setTile(false);
    }

    // The tile's choices, written to the keys so that Control and `ame` see them
    choose(id) {
        this._settings.set_string('filter', id);
        this._settings.set_boolean('filter-on', true);
    }

    setOn(on) {
        this._settings.set_boolean('filter-on', on);
    }

    setStrength(value) {
        this._settings.set_int('filter-strength', value);
    }

    sync() {
        const filter = this._settings.get_string('filter');
        const chosen = FILTERS.includes(filter);
        const on = chosen && this._settings.get_boolean('filter-on');
        const strength = this._settings.get_int('filter-strength');
        this._setEffect(on ? filterMatrix(filter, strength / 100) : null);
        this._setTile(chosen);
        this._tile?.sync(filter, on, strength);
    }

    _setEffect(matrix) {
        const group = Main.layoutManager.uiGroup;
        if (matrix && !this._effect) {
            this._effect = new FilterEffect(e => this._failed(e));
            this._effect.setMatrix(matrix);
            group.add_effect_with_name(EFFECT_NAME, this._effect);
            Main.layoutManager.connectObject('monitors-changed', () => {
                if (this._effect)
                    this._effect.failed = false;
                this._effect?.release();
            }, this);
            global.compositor.disable_unredirect();
            this._unredirected = true;
        } else if (matrix) {
            this._effect.setMatrix(matrix);
        } else if (this._effect) {
            Main.layoutManager.disconnectObject(this);
            group.remove_effect(this._effect);
            // The screens' textures go now, not when the collector comes
            this._effect.release();
            this._effect = null;
        }
        if (!this._effect && this._unredirected) {
            global.compositor.enable_unredirect();
            this._unredirected = false;
        }
    }

    // A screen too large for the GPU to hold its picture: it is drawn unfiltered, and the person is told once a session
    _failed(error) {
        console.warn(`Amethystora UI: the colour filter cannot be drawn on this screen: ${error.message}`);
        if (toldTooLarge)
            return;
        toldTooLarge = true;
        Main.notify(_('Colour filter'), _('A screen is too large for the colour filter, and is shown without it.'));
    }

    _setTile(shown) {
        if (shown && !this._indicator) {
            this._indicator = new SystemIndicator();
            this._tile = new FilterTile(this);
            this._indicator.quickSettingsItems.push(this._tile);
            Main.panel.statusArea.quickSettings.addExternalIndicator(this._indicator);
        } else if (!shown && this._indicator) {
            this._tile.destroy();
            this._tile = null;
            this._indicator.destroy();
            this._indicator = null;
        }
    }

    state() {
        return {
            effect: !!Main.layoutManager.uiGroup.get_effect(EFFECT_NAME),
            applied: !!this._effect && !this._effect.failed,
            tile: !!this._tile,
            unredirectHeld: this._unredirected,
            bytes: this._effect?.bytes ?? 0,
        };
    }
}
