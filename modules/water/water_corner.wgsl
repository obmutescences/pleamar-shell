// One rounded corner of the ring.  The corner tile is 46 px (Island) or 92 px
// (Frame); the arc radius is 46, tangent to the straight strips, so the depth
// matches at the joins.  The Frame tile also fills the square inner corner of
// the glass rails, turning it into a rounded glass wedge.
//
// values: a.x .. b.y six bands; b.z packs wave-height hundredths * 100 +
//   blend hundredths; b.w packs code + ripples*1000 + amplitude*0.1:
//   0..3 Island TL/TR/BL/BR, 10..13 Frame, +100 while water plays.

fn band_at(b: array<f32, 6>, t: f32, blend: f32) -> f32 {
    // Match the non-cyclic endpoint mapping used by water.wgsl.  Wrapping
    // t=1 back to band 0 made the right/bottom corners jump at the joins.
    let x = clamp(t, 0.0, 1.0) * 5.0;
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
    let z = s.b.z;
    let hcode = floor(z / 1000.0);
    let height = clamp(hcode / 100.0, 0.0, 3.0);
    let blend = clamp((z - hcode * 1000.0) / 100.0, 0.0, 1.0);
    //  b.w packs: code + ripples*1000 + amplitude*0.1.
    let raw = s.b.w;
    let ripples = floor(raw / 1000.0);
    let rem = raw - ripples * 1000.0;
    var code = floor(rem);
    let amp = clamp((rem - code) * 10.0, 0.2, 2.2);
    var water_on = false;
    if (code >= 100.0) {
        water_on = true;
        code = code - 100.0;
    }
    var is_frame = false;
    if (code >= 9.5) {
        is_frame = true;
        code = code - 10.0;
    }

    // Both ends of a corner arc meet the same end of the adjacent straight
    // edges.  Hold that endpoint at the join and ease only a small amount
    // toward the interior spectrum so the corner stays lively without a
    // half-spectrum jump.
    var endpoint = 0.0;
    if (code >= 0.5 && code < 2.5) {
        endpoint = 1.0;
    }

    let tile = s.size.x;
    let radius = 46.0;
    var x = s.pos.x;
    var y = s.pos.y;
    if (code > 0.5 && code < 1.5) {
        x = tile - x;
    } else if (code >= 1.5 && code < 2.5) {
        y = tile - y;
    } else if (code >= 2.5) {
        x = tile - x;
        y = tile - y;
    }

    let dx = x - tile;
    let dy = y - tile;
    let dist = sqrt(dx * dx + dy * dy);
    let depth = radius - dist;

    let theta = atan2(-dy, -dx);
    let arc = clamp(theta / 1.5707963, 0.0, 1.0);
    let corner_ease = sin(arc * 3.14159265);
    let sample_offset = 0.16 * corner_ease * corner_ease;
    var wave_u = endpoint;
    if (endpoint < 0.5) {
        wave_u = sample_offset;
    } else {
        wave_u = 1.0 - sample_offset;
    }

    var color = vec3<f32>(0.0);
    var alpha = 0.0;

    //  The rounded glass wedge, matching the rails' tint and opacity.
    if (is_frame && dist > radius && x > 46.0 && y > 46.0) {
        color = vec3<f32>(0.047, 0.102, 0.118);
        alpha = 0.88;
    }

    //  The edge light around the arc.
    if (abs(dist - radius) < 0.9) {
        color = s.color.rgb;
        alpha = max(alpha, 0.20);
    }

    if (water_on && depth >= 0.0 && depth < 60.0) {
        let spec = band_at(bands, wave_u, blend);
        let level = pow(clamp(spec, 0.0, 1.0), 0.82);
        let drive = smoothstep(0.04, 0.86, level);
        let pulse = smoothstep(0.18, 0.82, clamp(bands[0], 0.0, 1.0));
        let breath = sin(wave_u * 6.28318 + s.time * 0.22) * (0.5 + 1.8 * drive);
        var ripple = sin(wave_u * 6.28318 * 9.0 - s.time * 1.6) * 2.8;
        if (ripples > 1.5) {
            ripple = ripple + sin(wave_u * 6.28318 * 15.0 + s.time * 2.2) * 1.7;
        }
        if (ripples > 2.5) {
            ripple = ripple + sin(wave_u * 6.28318 * 23.0 - s.time * 2.7) * 1.25;
        }
        if (ripples > 3.5) {
            ripple = ripple + sin(wave_u * 6.28318 * 33.0 + s.time * 3.2) * 0.95;
        }
        if (ripples > 4.5) {
            ripple = ripple + sin(wave_u * 6.28318 * 45.0 - s.time * 3.7) * 0.75;
        }
        if (ripples > 5.5) {
            ripple = ripple + sin(wave_u * 6.28318 * 59.0 + s.time * 4.2) * 0.60;
        }
        if (ripples > 6.5) {
            ripple = ripple + sin(wave_u * 6.28318 * 75.0 - s.time * 4.7) * 0.48;
        }
        if (ripples > 7.5) {
            ripple = ripple + sin(wave_u * 6.28318 * 93.0 + s.time * 5.2) * 0.40;
        }
        if (ripples > 8.5) {
            ripple = ripple + sin(wave_u * 6.28318 * 113.0 - s.time * 5.7) * 0.33;
        }
        if (ripples > 9.5) {
            ripple = ripple + sin(wave_u * 6.28318 * 135.0 + s.time * 6.2) * 0.28;
        }
        ripple = ripple / sqrt(max(ripples, 1.0));
        let reach = clamp((3.0 + level * 32.0 + pulse * 10.0 + breath
            + ripple * (0.35 + 0.9 * drive) * height * 2.5) * amp, 4.0, 64.0);
        let ratio = depth / max(reach, 1.0);
        let aa = 1.5 / max(reach, 1.0);

        let body = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, ratio);
        let rim = exp(-abs(ratio - 1.0) / mix(0.035, 0.09, blend));
        let core = exp(-abs(ratio - 1.0) / mix(0.012, 0.032, blend));
        let halo = exp(-max(0.0, ratio - 1.0) * mix(16.0, 6.0, blend)) * (1.0 - body);
        let crest = smoothstep(0.30, 0.96, clamp(ratio, 0.0, 1.0));
        let root = exp(-clamp(ratio, 0.0, 1.0) * 5.0);

        var fill = body * (root * 0.10 + crest * (0.22 + level * 0.24));
        fill += rim * (0.22 + level * 0.24);
        fill += core * (0.32 + level * 0.32);
        fill += halo * (0.05 + level * 0.10);

        let hue = wave_u + ratio * 0.20;
        var wc = palette(s.color.rgb, s.color2.rgb, hue);
        wc = mix(wc, vec3<f32>(1.0, 1.0, 1.0),
            (rim * 0.28 + core * 0.60) * (0.7 + level * 0.3));

        if (fill > alpha) {
            color = wc;
            alpha = fill;
        }
    }

    return vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(1.0)), clamp(alpha, 0.0, 0.95));
}
