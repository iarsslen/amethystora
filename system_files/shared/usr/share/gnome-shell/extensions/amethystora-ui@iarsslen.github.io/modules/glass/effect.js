// The effect each glass surface carries: before the surface paints itself, the glass is drawn under it, cut from the
// frosted picture of the screen at the very spot the surface shows on, so the frost stays still while the surface
// moves over it. Being part of the surface's own paint, the glass follows it through every animation, fade and clip
// with no work of its own, and costs nothing while the surface is not drawn. A surface fading in or out is clearer as
// it is fainter, and one across two screens is cut from each screen's picture where it lies on that screen.

import Clutter from 'gi://Clutter';
import GObject from 'gi://GObject';
import Graphene from 'gi://Graphene';
import St from 'gi://St';

// What each material is made of: the picture it is cut from (frost.js), a brightness factor, a share of white, and
// the lens. The lens pulls the picture inwards near the edge: `pull` pixels at the very edge, dying away as
// exp(-(d / reach) ^ steep) with the distance d from it, which bends the picture over the rim; `glint` is the light
// on the rim, `shade` the darkening towards the bottom and `fringe` how much further the red is pulled than the blue.
export const MATERIALS = {
    'glass': {
        picture: 'glass', dim: 1, tint: 0.16,
        pull: 12.8, reach: 7.28, steep: 1.59, glint: 0.08, shade: 0.044, fringe: 0.024,
    },
    'dock': {
        picture: 'glass', dim: 1, tint: 0.16,
        pull: 16.8, reach: 8.56, steep: 1.71, glint: 0.09, shade: 0.048, fringe: 0.028,
    },
    'menu-bar': {
        picture: 'glass', dim: 0.85, tint: 0,
        pull: 0, reach: 1, steep: 1, glint: 0, shade: 0, fringe: 0,
    },
    'frost': {
        picture: 'frost', dim: 1, tint: 0,
        pull: 0, reach: 1, steep: 1, glint: 0, shade: 0, fringe: 0,
    },
};

// A look is what a surface asks of its glass:
//   material  one of MATERIALS
//   radius    the corners, in the stylesheet's pixels, or null for the surface's own border-radius, as the desktop
//             style's stylesheet gives it (themed/shell-styles.css.tpl): the pane then always has the corners
//             GNOME draws the surface with
//   shadow    {alpha, blur, offset} of a drop shadow outside the outline, in stylesheet pixels, or null
//   ring      the strength of a hairline just outside the outline, or 0
//   areas     (actor) => [[x, y, width, height], ...] in the actor's own pixels, where the glass goes when that is
//             not the whole actor
//   content   (actor) => the opacity to draw the surface itself with over its glass, or -1 for its own
//   fade      (y) => a share of the glass's opacity for a surface whose top is at y on the stage
//   inClones  whether the glass is drawn when the surface is painted as a copy elsewhere (as the magnifier does)
//   stageOnly whether the glass is left out when the surface is painted on its own, as a window is for a screenshot
//             of it or to be shared: the picture is then the surface bare, at full opacity
export const GlassEffect = GObject.registerClass(
class AmethystoraGlassEffect extends Clutter.Effect {
    _init(glass, look) {
        super._init();
        this._glass = glass;
        this.look = look;
        this._pipelines = new Map();
        this._textures = new Map();
        this._pictures = new Set();
    }

    // A changed look (a window maximized, the colour scheme switched) shows on the next frame
    update(changes) {
        Object.assign(this.look, changes);
        this.get_actor()?.queue_redraw();
    }

    // Lets go of the pictures, for an effect taken off its surface
    forget() {
        for (const picture of this._pictures)
            picture.consumers.delete(this);
        this._pictures.clear();
        this._pipelines = new Map();
        this._textures = new Map();
    }

    _scale() {
        return St.ThemeContext.get_for_stage(global.stage).scale_factor;
    }

    // How far outside the surface the glass draws: its shadow and its ring
    _margin() {
        const {shadow, ring} = this.look;
        const reach = shadow ? shadow.blur + Math.abs(shadow.offset) : 0;
        return Math.ceil(Math.max(reach, ring ? 2 : 0) * this._scale());
    }

    vfunc_modify_paint_volume(volume) {
        const margin = this._margin();
        if (margin > 0) {
            const origin = volume.get_origin();
            volume.set_origin(new Graphene.Point3D({x: origin.x - margin, y: origin.y - margin, z: origin.z}));
            volume.set_width(volume.get_width() + 2 * margin);
            volume.set_height(volume.get_height() + 2 * margin);
        }
        return true;
    }

    // Whether this is a paint of the actor by itself and not a part of the screen: the screen is painted with the
    // region being redrawn, and a paint of one actor into its own picture has none
    _alone(paintContext) {
        return !!this.look.stageOnly && typeof paintContext.get_redraw_clip === 'function' &&
            !paintContext.get_redraw_clip();
    }

    vfunc_paint_node(node, paintContext, _flags) {
        const actor = this.get_actor();
        let content = -1;
        if (!this._alone(paintContext) && (this.look.inClones || !actor.is_in_clone_paint()) &&
            this._paintGlass(node, paintContext, actor))
            content = this.look.content?.(actor) ?? -1;
        node.add_child(new Clutter.ActorNode(actor, content));
    }

    _paintGlass(node, paintContext, actor) {
        const look = this.look;
        const material = MATERIALS[look.material];
        const width = actor.width;
        const height = actor.height;
        if (!material || width < 1 || height < 1)
            return false;
        // Where the actor is on the stage, as drawn: through every transformation of it and its parents
        const extents = actor.get_transformed_extents();
        const sx = extents.size.width / width;
        const sy = extents.size.height / height;
        const opacity = actor.get_paint_opacity() / 255;
        if (opacity <= 0 || sx <= 0 || sy <= 0)
            return false;

        const scale = this._scale();
        const margin = this._margin();
        const areas = look.areas?.(actor) ?? [[0, 0, width, height]];
        // The theme node's lengths are already in device pixels
        const radius = look.radius ?? (actor.get_theme_node?.()?.get_border_radius(St.Corner.TOPLEFT) ?? 0) / scale;
        const frost = this._glass.frost;
        let drawn = false;
        areas.forEach(([x, y, w, h], i) => {
            if (w < 1 || h < 1)
                return;
            const left = extents.origin.x + x * sx;
            const top = extents.origin.y + y * sy;
            const fade = look.fade?.(top) ?? 1;
            if (fade <= 0)
                return;
            // The quad covers the surface and its shadow, here on the stage. Each screen it reaches draws its own part
            // from its own picture, so that a pane across two screens shows on each the frost of that screen's
            // wallpaper; the lens is worked out for the whole pane, so the parts meet without a seam.
            const quad = [left - margin * sx, top - margin * sy, left + (w + margin) * sx, top + (h + margin) * sy];
            for (const picture of frost.pictures(material.picture)) {
                const monitor = picture.monitor;
                const x1 = Math.max(quad[0], monitor.x);
                const y1 = Math.max(quad[1], monitor.y);
                const x2 = Math.min(quad[2], monitor.x + monitor.width);
                const y2 = Math.min(quad[3], monitor.y + monitor.height);
                if (x2 <= x1 || y2 <= y1)
                    continue;
                // Drawn again whenever the picture changes, ready or not
                picture.consumers.add(this);
                this._pictures.add(picture);
                if (!picture.ready || !picture.texture)
                    continue;
                // As far as the surface is see-through while it fades, its frost is clear too
                const clear = frost.picture(monitor.index, 'clear');
                const sharp = clear?.ready && clear.texture ? clear.texture : null;
                const pipeline = this._pipeline(paintContext, `${i}:${monitor.index}`, picture.texture, sharp);

                const shader = this._glass.shader;
                const [ux, uy] = [1 / monitor.width, 1 / monitor.height];
                shader.set(pipeline, 'u_origin', (left - monitor.x) * ux, (top - monitor.y) * uy);
                shader.set(pipeline, 'u_pixel', ux, uy);
                shader.set(pipeline, 'u_size', w * sx, h * sy);
                // No rounder than half the shorter side, as St draws a pill
                shader.set(pipeline, 'u_radius', Math.min(radius * scale * sx, w * sx / 2, h * sy / 2));
                shader.set(pipeline, 'u_opacity', opacity * fade);
                shader.set(pipeline, 'u_frost', sharp ? opacity * fade : 1);
                shader.set(pipeline, 'u_dim', material.dim);
                shader.set(pipeline, 'u_tint', material.tint);
                shader.set(pipeline, 'u_pull', material.pull * scale * sx);
                shader.set(pipeline, 'u_reach', material.reach * scale * sx);
                shader.set(pipeline, 'u_steep', material.steep);
                shader.set(pipeline, 'u_glint', material.glint);
                shader.set(pipeline, 'u_shade', material.shade);
                shader.set(pipeline, 'u_fringe', material.fringe);
                const shadow = look.shadow;
                shader.set(pipeline, 'u_shadow',
                    shadow ? shadow.alpha : 0,
                    shadow ? shadow.blur * scale * sy : 0,
                    shadow ? shadow.offset * scale * sy : 0,
                    look.ring ?? 0);

                // The part in the actor's own pixels, and where it falls on its screen
                const box = new Clutter.ActorBox({
                    x1: x - margin + (x1 - quad[0]) / sx,
                    y1: y - margin + (y1 - quad[1]) / sy,
                    x2: x - margin + (x2 - quad[0]) / sx,
                    y2: y - margin + (y2 - quad[1]) / sy,
                });
                const pipelineNode = new Clutter.PipelineNode(pipeline);
                node.add_child(pipelineNode);
                pipelineNode.add_texture_rectangle(box,
                    (x1 - monitor.x) * ux, (y1 - monitor.y) * uy, (x2 - monitor.x) * ux, (y2 - monitor.y) * uy);
                drawn = true;
            }
        });
        return drawn;
    }

    // One pipeline for each area and screen, with that screen's pictures: the frosted one, and the sharp one when
    // there is one (else the frosted one again, which the shader then never mixes in)
    _pipeline(paintContext, key, texture, sharp) {
        const shader = this._glass.shader;
        let pipeline = this._pipelines.get(key);
        if (!pipeline) {
            pipeline = shader.pipeline(paintContext.get_framebuffer().get_context());
            shader.setInt(pipeline, 'u_picture', 0);
            shader.setInt(pipeline, 'u_clear', 1);
            this._pipelines.set(key, pipeline);
        }
        // Only a changed picture makes a new pair: this runs on every paint
        const clear = sharp ?? texture;
        const held = this._textures.get(key);
        if (held?.[0] !== texture || held?.[1] !== clear) {
            if (held?.[0] !== texture)
                pipeline.set_layer_texture(0, texture);
            if (held?.[1] !== clear)
                pipeline.set_layer_texture(1, clear);
            this._textures.set(key, [texture, clear]);
        }
        return pipeline;
    }
});
