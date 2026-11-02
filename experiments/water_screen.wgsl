// A single water ring around the whole screen, in one full-screen shader.
// The ring follows a rounded rectangle offset by `inset` pixels from the
// screen edge: 0 for the Island, the rail thickness for the Frame.  Because
// the distance field is one rounded rectangle, the four corners are real
// arcs, not two strips meeting at 90 degrees.
//
// values: a.x .. b.y six spectrum bands, b.z blend, b.w inset in pixels.

fn band_at(b: array<f32, 6>, t: f32, blend: f32) -> f32 {
    let x = fract(t) * 6.0;
    let i = i32(floor(x));
    let f = fract(x);
    let i0 = i32(clamp(f32(i - 1), 0.0, 5.0));
    let i1 = i32(clamp(f32(i), 0.0, 5.0));
    let i2 = i32(clamp(f32(i + 1), 0.0, 5.0));
    let i3 = i32(clamp(f32(i + 2), 0.0, 5.0));
    let p0 = b[i0];
    let p1 = b[i1];
    let p2 = b[i2];
    let p3 = b[i3];
    let linear = mix(p1, p2, smoothstep(0.0, 1.0, f));
    let catmull = 0.5 * ((2.0 * p1)
        + (-p0 + p2) * f
        + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f * f
        + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * f * f * f);
    return clamp(mix(linear, catmull, clamp(blend, 0.0, 1.0)), 0.0, 1.0);
}

fn palette(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
    let x = fract(t) * 2.0;
    if (x < 1.0) {
        return mix(a, b, smoothstep(0.0, 1.0, x));
    }
    return mix(b, a, smoothstep(0.0, 1.0, x - 1.0));
}

fn shade(s: Shader) -> vec4<f32> {
    var bands: array<f32, 6> = array<f32, 6>(s.a.x, s.a.y, s.a.z, s.a.w, s.b.x, s.b.y);
    let blend = clamp(s.b.z, 0.0, 1.0);
    let inset = clamp(s.b.w, 0.0, 240.0);

    let half = s.size * 0.5;
    let inner_half = max(half - vec2<f32>(inset, inset), vec2<f32>(1.0, 1.0));
    let radius = min(18.0, min(inner_half.x, inner_half.y));
    let q = abs(s.pos - half) - (inner_half - vec2<f32>(radius, radius));
    let sd = length(max(q, vec2<f32>(0.0, 0.0))) + min(max(q.x, q.y), 0.0) - radius;
    let depth = -sd;

    // Everything more than 90 px inside the ring is empty; the early out keeps
    // the full-screen surface cheap for the card.
    if (depth < -2.0 || depth > 90.0) {
        return vec4<f32>(0.0, 0.0, 0.0, 0.0);
    }

    // One angle around the screen: the spectrum and the ripples wrap without a
    // seam at any corner.
    let ang = atan2(s.pos.y - half.y, s.pos.x - half.x) / 6.28318 + 0.5;
    let spec = band_at(bands, ang, blend);
    let level = pow(clamp(spec, 0.0, 1.0), 0.82);
    let bass = max(bands[0], bands[1]);
    let treble = max(bands[4], bands[5]);
    let energy = clamp(max(max(bass, bands[2]), max(bands[3], treble)), 0.0, 1.0);

    // Pixels, not a fraction of a strip: the ring is the same depth on a 120 px
    // strip and in the corner arc.
    let breath = sin(ang * 6.28318 * 2.0 + s.time * 0.22) * 1.3;
    let ripple = sin(ang * 6.28318 * 80.0 - s.time * 2.0) * 2.0
        + sin(ang * 6.28318 * 137.0 + s.time * 3.1) * 1.2
        + sin(ang * 6.28318 * 223.0 - s.time * 4.2) * 0.7;
    let reach = clamp(8.0 + level * 22.0 + breath + ripple * (0.55 + level * 0.45),
        3.0, 42.0);
    let ratio = depth / max(reach, 1.0);
    let aa = 1.5 / max(reach, 1.0);

    let body = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, ratio);
    let rim = exp(-abs(ratio - 1.0) / mix(0.035, 0.09, blend));
    let core = exp(-abs(ratio - 1.0) / mix(0.012, 0.032, blend));
    let halo = exp(-max(0.0, ratio - 1.0) * mix(16.0, 6.0, blend)) * (1.0 - body);
    let crest = smoothstep(0.30, 0.96, clamp(ratio, 0.0, 1.0));
    let root = exp(-clamp(ratio, 0.0, 1.0) * 5.0);

    let sheen_center = 0.62 + sin(ang * 6.28318 * 2.0 + s.time * 0.33) * 0.12;
    let sheen_dx = (ratio - sheen_center) / 0.16;
    let sheen = exp(-sheen_dx * sheen_dx) * body;
    let caustic_wave = 0.5 + 0.5 * sin(ratio * 9.0 + ang * 6.28318 * 3.0
        - s.time * 0.95 + sin(ang * 6.28318 * 2.0 + ratio * 3.0) * 0.7);
    let caustic = pow(caustic_wave, 8.0) * body
        * (0.035 + treble * 0.10 + energy * 0.06);
    let echo = exp(-abs(ratio - (1.16 + level * 0.06)) / 0.09);
    let inner_ratio = 0.52 + 0.04 * sin(ang * 6.28318 * 90.0 - s.time * 2.4);
    let inner = exp(-abs(ratio - inner_ratio) / 0.055) * body;
    let streak_wave = 0.5 + 0.5 * sin(ang * 6.28318 * 7.0 + ratio * 3.0
        + sin(ang * 6.28318 * 3.0 + s.time * 0.4) * 0.9);
    let streak = pow(streak_wave, 12.0) * body * (0.02 + level * 0.05);

    var fill = body * (root * 0.10 + crest * (0.22 + level * 0.24));
    fill += rim * (0.20 + level * 0.22);
    fill += core * (0.30 + level * 0.30);
    fill += halo * (0.05 + level * 0.10);
    fill += sheen * body * 0.10 * (0.4 + level);
    fill += echo * (0.05 + level * 0.06);
    fill += inner * (0.05 + level * 0.08);
    fill += caustic + streak;

    let hue = ang + 0.10 * sin(s.time * 0.12 + ang * 6.28318 * 1.3)
        + ratio * 0.22 + caustic * 0.25;
    var color = palette(s.color.rgb, s.color2.rgb, hue);
    color = mix(color, vec3<f32>(1.0, 1.0, 1.0),
        (rim * 0.25 + core * 0.55) * (0.7 + level * 0.3));
    color = mix(color, s.color.rgb, streak * 2.0);
    color = mix(color, s.color2.rgb * 0.35, body * 0.10);

    return vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(1.0)), clamp(fill, 0.0, 0.95));
}
