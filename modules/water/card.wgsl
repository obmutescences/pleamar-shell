//  A card-shaped water tank for the Overview resource tiles.  The card is the
//  container: the water fills its rounded rectangle from the bottom to the
//  measured percentage, and the surface keeps moving so each sample reads as
//  a level rather than a progress bar.
//
//  values: a.x = level 0..1, a.y = phase offset, a.z = hover 0..1.
//  The shader clips itself to the card's rounded rectangle, so the backing
//  card, border and text can stay ordinary scene primitives.

fn sd_round_box(p: vec2<f32>, half_size: vec2<f32>, radius: f32) -> f32 {
    let q = abs(p) - (half_size - vec2<f32>(radius, radius));
    return length(max(q, vec2<f32>(0.0, 0.0)))
        + min(max(q.x, q.y), 0.0) - radius;
}

fn shade(s: Shader) -> vec4<f32> {
    let level = clamp(s.a.x, 0.0, 1.0);
    if (level < 0.001) {
        return vec4<f32>(0.0, 0.0, 0.0, 0.0);
    }

    //  Rounded card mask.  A two-pixel feather keeps the water from showing a
    //  hard square edge behind the card's 16 px corner.
    let half_size = s.size * 0.5;
    let p = (s.uv - vec2<f32>(0.5, 0.5)) * s.size;
    let dist = sd_round_box(p, half_size, 16.0);
    let mask = 1.0 - smoothstep(-1.2, 0.6, dist);
    if (mask <= 0.001) {
        return vec4<f32>(0.0, 0.0, 0.0, 0.0);
    }

    let phase = s.a.y * 6.28318;
    let t = s.time;
    let x = s.uv.x;
    let y = s.uv.y * s.size.y;
    let surface = (1.0 - level) * s.size.y;

    //  Three faster, unrelated trains: one broad swell, one shorter chop and
    //  a fine ripple.  The hover value only makes the surface a little more
    //  inquisitive; the level itself stays honest.
    let hover = clamp(s.a.z, 0.0, 1.0);
    let amp = (2.4 + 6.2 * smoothstep(0.0, 0.9, level)) * (1.0 + hover * 0.5);
    let wave = sin(x * 6.28318 * 1.15 + t * 1.28 + phase) * 0.60
        + sin(x * 6.28318 * 2.7 - t * 1.86 + phase * 1.7) * 0.28
        + sin(x * 6.28318 * 5.3 + t * 2.58 + phase * 2.3) * 0.12;
    let surface_y = clamp(surface + wave * amp, 1.0, s.size.y - 2.0);

    let below = smoothstep(surface_y - 1.4, surface_y + 1.4, y);
    let depth = clamp((y - surface_y) / max(s.size.y, 1.0), 0.0, 1.0);

    //  Body: transparent enough that ink labels survive even at 100 %, but a
    //  slow vertical drift keeps the whole tank moving, not just its rim.
    let drift = 0.5 + 0.5 * sin(y * 0.085 - t * 1.35 + x * 2.4 + phase);
    let body = below * (0.19 + 0.06 * smoothstep(0.0, 0.7, level) + 0.035 * depth)
        * (0.86 + 0.22 * drift);

    //  Crossing caustic sheets inside the body.
    let c1 = sin((x * 8.5 + depth * 2.4) * 6.28318 + t * 0.92 + phase);
    let c2 = sin((x * 3.2 - depth * 5.0) * 6.28318 - t * 0.68 + phase * 1.4);
    let caustic = pow(clamp(0.5 + 0.30 * c1 + 0.20 * c2, 0.0, 1.0), 4.5);
    let caustic_alpha = caustic * below * (0.055 + 0.080 * level);

    //  A bright meniscus at the surface, fast travelling glints on it, and a
    //  faint halo above it.
    let line = exp(-abs(y - surface_y) / (1.15 + 0.35 * level));
    let halo = exp(-abs(y - surface_y) / 8.0);
    let crest = line * (0.40 + 0.30 * smoothstep(0.0, 1.0, level));
    let glint = pow(0.5 + 0.5 * sin(x * 6.28318 * 6.0 - t * 2.8 + phase * 2.0), 9.0);
    let glint_alpha = glint * line * (0.18 + 0.24 * level);

    var color = s.color.rgb;
    color = mix(color, vec3<f32>(1.0, 1.0, 1.0),
        clamp(crest * 0.58 + caustic * 0.30 + glint * 0.30, 0.0, 0.78));

    let alpha = mask * clamp(body + caustic_alpha + crest + glint_alpha + halo * 0.04, 0.0, 0.92);
    return vec4<f32>(color, alpha);
}
