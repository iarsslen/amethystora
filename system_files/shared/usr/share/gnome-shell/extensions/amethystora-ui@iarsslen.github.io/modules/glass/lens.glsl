// The glass, drawn under a surface from the frosted picture of its screen (modules/glass/frost.js). Every length is
// in screen pixels, measured from the top left of the surface. Inside the surface's rounded outline the picture is
// bent outwards near the edges, as through the rim of a thick lens, lit along the rim, made milky and shaded towards
// the bottom; outside it, a soft drop shadow. While the surface fades in or out the frost condenses or clears with
// it: the picture is mixed towards the screen's sharp one, and the darkening eased off, as far as it is see-through.
// Written for Amethystora (Apache-2.0).

uniform sampler2D u_picture;
// The same spot unblurred, and how frosted the glass is: 1 as made, 0 clear
uniform sampler2D u_clear;
uniform float u_frost;
// Where the surface's top left falls in the picture, and how much of the picture one pixel is
uniform vec2 u_origin;
uniform vec2 u_pixel;
uniform vec2 u_size;
uniform float u_radius;
uniform float u_opacity;
// The material: a brightness factor, a share of white mixed in, and the lens (how far the picture is pulled at the
// very edge, over what distance and how steeply that dies away, the rim's light, the darkening at the bottom and how
// much further the red is pulled than the blue)
uniform float u_dim;
uniform float u_tint;
uniform float u_pull;
uniform float u_reach;
uniform float u_steep;
uniform float u_glint;
uniform float u_shade;
uniform float u_fringe;
// The drop shadow (its strength, its blur and how far down it falls) and a hairline ring just outside the outline
uniform vec4 u_shadow;

// Signed distance to a rounded rectangle centred on the origin: negative inside
float glass_outline(vec2 p, vec2 half_size, float radius)
{
    vec2 q = abs(p) - half_size + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// The way out of the outline at p: straight out of the nearest side, or away from a corner's centre
vec2 glass_outwards(vec2 p, vec2 half_size, float radius)
{
    vec2 q = abs(p) - half_size + radius;
    vec2 away;
    if (q.x > 0.0 && q.y > 0.0)
        away = normalize(q);
    else if (q.x > q.y)
        away = vec2(1.0, 0.0);
    else
        away = vec2(0.0, 1.0);
    return away * vec2(p.x < 0.0 ? -1.0 : 1.0, p.y < 0.0 ? -1.0 : 1.0);
}

vec3 glass_sample(vec2 at)
{
    vec2 spot = u_origin + at * u_pixel;
    vec3 frosted = texture2D(u_picture, spot).rgb;
    if (u_frost >= 1.0)
        return frosted;
    return mix(texture2D(u_clear, spot).rgb, frosted, u_frost);
}

vec4 glass_color()
{
    vec2 p = (cogl_tex_coord_in[0].st - u_origin) / u_pixel;
    vec2 half_size = u_size * 0.5;
    float radius = min(u_radius, min(half_size.x, half_size.y));
    vec2 centred = p - half_size;
    float edge = glass_outline(centred, half_size, radius);
    vec4 color = vec4(0.0);

    if (edge < 0.5) {
        float depth = max(-edge, 0.0);
        vec3 picture;
        float pull = u_pull > 0.0 ? u_pull * exp(-pow(depth / u_reach, u_steep)) : 0.0;
        if (pull > 0.01) {
            // The picture shown here comes from further in, the red a little further than the blue
            vec2 inwards = -glass_outwards(centred, half_size, radius);
            picture.r = glass_sample(p + inwards * pull * (1.0 + u_fringe)).r;
            picture.g = glass_sample(p + inwards * pull).g;
            picture.b = glass_sample(p + inwards * pull * (1.0 - u_fringe)).b;
        } else {
            picture = glass_sample(p);
        }

        picture *= mix(1.0, u_dim, u_frost);
        picture = mix(picture, vec3(1.0), u_tint);

        if (u_glint > 0.0) {
            // Light caught by the rim: strongest on the outermost pixels, with a faint long tail, and weaker over
            // dark parts of the picture, more so away from the edge. Added as a screen, so it never darkens.
            float light = u_glint * (0.75 * exp(-pow(depth / 2.0, 2.0)) + 0.25 * exp(-depth / 6.0));
            float luma = dot(picture, vec3(0.2126, 0.7152, 0.0722));
            light *= mix(mix(0.8, 0.5, clamp(depth / 8.0, 0.0, 1.0)), 1.0, luma);
            picture += (vec3(1.0) - picture) * light;
        }

        if (u_shade > 0.0)
            picture *= 1.0 - u_shade * smoothstep(0.25, 1.0, p.y / u_size.y);

        float cover = clamp(0.5 - edge, 0.0, 1.0);
        color = vec4(picture, 1.0) * cover;
    }

    if (u_shadow.w > 0.0 && edge > -0.5) {
        // A hairline just outside the outline
        float ring = u_shadow.w * clamp(1.0 - abs(edge - 0.5), 0.0, 1.0);
        color += vec4(0.0, 0.0, 0.0, ring) * (1.0 - color.a);
    }

    if (u_shadow.x > 0.0) {
        float below = glass_outline(centred - vec2(0.0, u_shadow.z), half_size, radius);
        float shadow = u_shadow.x * (1.0 - smoothstep(-u_shadow.y, u_shadow.y, below));
        color += vec4(0.0, 0.0, 0.0, shadow) * (1.0 - color.a);
    }

    return color * u_opacity;
}
