// The effect each glass surface carries: before the surface paints itself, the glass is drawn under it, cut from the
// frosted picture of the screen at the very spot the surface shows on, so the frost stays still while the surface
// moves over it. Being part of the surface's own paint, the glass follows it through every animation, fade and clip
// with no work of its own, and costs nothing while the surface is not drawn.

import Clutter from 'gi://Clutter';
import GObject from 'gi://GObject';
import Graphene from 'gi://Graphene';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

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

// The screen a point of the stage is on, or the main one
function monitorAt(x, y) {
    for (const monitor of Main.layoutManager.monitors) {
        if (x >= monitor.x && x < monitor.x + monitor.width && y >= monitor.y && y < monitor.y + monitor.height)
            return monitor.index;
    }
    return Main.layoutManager.primaryIndex;
}

// A look is what a surface asks of its glass:
//   material  one of MATERIALS
//   radius    the corners, in the stylesheet's pixels
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
        this._pipelines = [];
        this._textures = [];
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
        this._pipelines = [];
        this._textures = [];
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
        let drawn = false;
        areas.forEach(([x, y, w, h], i) => {
            if (w < 1 || h < 1)
                return;
            const left = extents.origin.x + x * sx;
            const top = extents.origin.y + y * sy;
            const picture = this._glass.frost.picture(monitorAt(left + w * sx / 2, top + h * sy / 2), material.picture);
            if (!picture)
                return;
            // Drawn again whenever the picture changes, ready or not
            picture.consumers.add(this);
            this._pictures.add(picture);
            if (!picture.ready || !picture.texture)
                return;
            const fade = look.fade?.(top) ?? 1;
            if (fade <= 0)
                return;

            const shader = this._glass.shader;
            let pipeline = this._pipelines[i];
            if (!pipeline) {
                pipeline = shader.pipeline(paintContext.get_framebuffer().get_context());
                shader.setInt(pipeline, 'u_picture', 0);
                this._pipelines[i] = pipeline;
            }
            if (this._textures[i] !== picture.texture) {
                pipeline.set_layer_texture(0, picture.texture);
                this._textures[i] = picture.texture;
            }

            const monitor = picture.monitor;
            const [ux, uy] = [1 / monitor.width, 1 / monitor.height];
            shader.set(pipeline, 'u_origin', (left - monitor.x) * ux, (top - monitor.y) * uy);
            shader.set(pipeline, 'u_pixel', ux, uy);
            shader.set(pipeline, 'u_size', w * sx, h * sy);
            shader.set(pipeline, 'u_radius', look.radius * scale * sx);
            shader.set(pipeline, 'u_opacity', opacity * fade);
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

            // The quad covers the surface and its shadow; its texture coordinates are where that falls on the screen
            const box = new Clutter.ActorBox({x1: x - margin, y1: y - margin, x2: x + w + margin, y2: y + h + margin});
            const pipelineNode = new Clutter.PipelineNode(pipeline);
            node.add_child(pipelineNode);
            pipelineNode.add_texture_rectangle(box,
                (left - margin * sx - monitor.x) * ux, (top - margin * sy - monitor.y) * uy,
                (left + (w + margin) * sx - monitor.x) * ux, (top + (h + margin) * sy - monitor.y) * uy);
            drawn = true;
        });
        return drawn;
    }
});
