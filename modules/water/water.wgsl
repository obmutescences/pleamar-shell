// Pleamar's water edge: one straight screen edge, as a thin glass meniscus
// with many small ripples.  Kept deliberately cheap: the body, one bright
// waterline, a halo and up to ten ripple trains; no caustics or texture passes.
//
// values: a.x .. b.y six spectrum bands (already depth-scaled); b.z packs
//         side * 100000 + height hundredths * 100 + blend hundredths; b.w
//         packs ripples * 10 + amplitude.

fn band_at(b: array<f32, 6>, t: f32, blend: f32) -> f32 {
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
    //  b.z packs side * 1e6, wave-height hundredths * 1000 and blend
    //  hundredths.  The thousand gap keeps blend=100 from carrying into the
    //  height code.
    let side_code = s.b.z;
    let side = floor(side_code / 1000000.0);
    let zrem = side_code - side * 1000000.0;
    let hcode = floor(zrem / 1000.0);
    let height = clamp(hcode / 100.0, 0.0, 3.0);
    let blend = clamp((zrem - hcode * 1000.0) / 100.0, 0.0, 1.0);
    let pack = s.b.w;
    let ripples = floor(pack / 10.0);
    let amp = clamp(pack - ripples * 10.0, 0.2, 2.2);

    var u = s.uv.x;
    var d = s.uv.y;
    if (side > 0.5 && side < 1.5) {
        u = 1.0 - s.uv.x;
        d = 1.0 - s.uv.y;
    } else if (side >= 1.5 && side < 2.5) {
        u = s.uv.y;
        d = s.uv.x;
    } else if (side >= 2.5) {
        u = 1.0 - s.uv.y;
        d = 1.0 - s.uv.x;
    }

    let spec = band_at(bands, u, blend);
    let level = pow(clamp(spec, 0.0, 1.0), 0.82);
    //  The water should answer the beat, not just breathe on its own clock.
    //  drive makes the time-based motion grow with the measured level, and
    //  the ripple trains use ten decreasing wavelengths for 1..10 ripples.
    let drive = smoothstep(0.04, 0.86, level);
    //  The bass is the beat: one slow envelope moves the whole edge, while
    //  level keeps the six local bands shaping the crest.
    let low = clamp(bands[0], 0.0, 1.0);
    let pulse = smoothstep(0.18, 0.82, low);
    let breath = sin(u * 6.28318 + s.time * 0.22) * (0.5 + 1.8 * drive);
    var ripple = sin(u * 6.28318 * 9.0 - s.time * 1.6) * 2.8;
    if (ripples > 1.5) {
        ripple = ripple + sin(u * 6.28318 * 15.0 + s.time * 2.2) * 1.7;
    }
    if (ripples > 2.5) {
        ripple = ripple + sin(u * 6.28318 * 23.0 - s.time * 2.7) * 1.25;
    }
    if (ripples > 3.5) {
        ripple = ripple + sin(u * 6.28318 * 33.0 + s.time * 3.2) * 0.95;
    }
    if (ripples > 4.5) {
        ripple = ripple + sin(u * 6.28318 * 45.0 - s.time * 3.7) * 0.75;
    }
    if (ripples > 5.5) {
        ripple = ripple + sin(u * 6.28318 * 59.0 + s.time * 4.2) * 0.60;
    }
    if (ripples > 6.5) {
        ripple = ripple + sin(u * 6.28318 * 75.0 - s.time * 4.7) * 0.48;
    }
    if (ripples > 7.5) {
        ripple = ripple + sin(u * 6.28318 * 93.0 + s.time * 5.2) * 0.40;
    }
    if (ripples > 8.5) {
        ripple = ripple + sin(u * 6.28318 * 113.0 - s.time * 5.7) * 0.33;
    }
    if (ripples > 9.5) {
        ripple = ripple + sin(u * 6.28318 * 135.0 + s.time * 6.2) * 0.28;
    }
    ripple = ripple / sqrt(max(ripples, 1.0));
    let reach = clamp((3.0 + level * 32.0 + pulse * 10.0 + breath
        + ripple * (0.35 + 0.9 * drive) * height * 2.5) * amp, 4.0, 64.0);
    var span = s.size.y;
    if (side >= 1.5) { span = s.size.x; }
    let ratio = d * span / max(reach, 1.0);
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

    let hue = u + ratio * 0.20;
    var color = palette(s.color.rgb, s.color2.rgb, hue);
    color = mix(color, vec3<f32>(1.0, 1.0, 1.0),
        (rim * 0.28 + core * 0.60) * (0.7 + level * 0.3));

    return vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(1.0)), clamp(fill, 0.0, 0.95));
}
