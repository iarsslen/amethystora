// A GLSL fragment shader as a Cogl pipeline, for drawing from Clutter's paint nodes (Clutter.Effect.vfunc_paint_node)
// rather than through Shell.GLSLEffect, which GNOME 51 no longer has. One template is compiled per GPU context and
// every user draws from a copy of it, which shares the compiled program but keeps its own uniforms and textures.

import Cogl from 'gi://Cogl';

export class Shader {
    // declarations: GLSL at the top level (uniforms, functions); code: the body run for each pixel, which sets
    // cogl_color_out. Layer 0 is the texture the shader samples, with linear filtering and its edges held.
    constructor(declarations, code) {
        this._declarations = declarations;
        this._code = code;
        this._templates = new Map();
        this._locations = new Map();
    }

    pipeline(context) {
        let template = this._templates.get(context);
        if (!template) {
            template = Cogl.Pipeline.new(context);
            template.set_layer_null_texture(0);
            template.set_layer_filters(0, Cogl.PipelineFilter.LINEAR, Cogl.PipelineFilter.LINEAR);
            template.set_layer_wrap_mode(0, Cogl.PipelineWrapMode.CLAMP_TO_EDGE);
            template.add_snippet(Cogl.Snippet.new(Cogl.SnippetHook.FRAGMENT, this._declarations, this._code));
            this._templates.set(context, template);
        }
        return template.copy();
    }

    _location(pipeline, name) {
        let location = this._locations.get(name);
        if (location === undefined) {
            location = pipeline.get_uniform_location(name);
            this._locations.set(name, location);
        }
        return location;
    }

    // A float uniform, or a vector of up to four
    set(pipeline, name, ...values) {
        const location = this._location(pipeline, name);
        if (location < 0)
            return;
        if (values.length === 1)
            pipeline.set_uniform_1f(location, values[0]);
        else
            pipeline.set_uniform_float(location, values.length, 1, values);
    }

    setInt(pipeline, name, value) {
        const location = this._location(pipeline, name);
        if (location >= 0)
            pipeline.set_uniform_1i(location, value);
    }

    destroy() {
        this._templates.clear();
        this._locations.clear();
    }
}
