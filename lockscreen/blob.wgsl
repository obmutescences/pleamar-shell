// The avatar's frame: an aurora blob that slowly morphs and turns (6 s to change shape, 9 s a turn), with a darker
// "ghost" blob set inside it that turns the other way. The avatar disc is drawn over the middle.
//
// colors: the accent's dark and light shades (mintlo, minthi). values: a = 1 shows it, 0 hides it (fade).

const TAU: f32 = 6.2831853;

fn edge(theta: f32, base: f32, t: f32, phase: f32) -> f32 {
    let m = TAU * t / 6.0 + phase;
    return base * (1.0
        + 0.060 * sin(2.0 * theta + m)
        + 0.045 * sin(3.0 * theta - m * 1.0 + 1.3)
        + 0.025 * sin(5.0 * theta + m * 2.0));
}

fn cover(d: f32, r: f32) -> f32 {
    return 1.0 - smoothstep(r - 0.75, r + 0.75, d);
}

fn shade(s: Shader) -> vec4<f32> {
    let p = s.pos - s.size * 0.5;
    let d = length(p);
    let ang = atan2(p.y, p.x);
    let t = s.time;

    // the aurora blob, turning one way
    let th1 = ang - TAU * t / 9.0;
    let r1 = edge(th1, 114.0, t, 0.0);
    let a1 = cover(d, r1);

    // the aurora gradient follows the blob's own turn, through the accent's own shades: dark, accent, light
    let g = 0.5 + 0.5 * sin(th1 + 0.8);
    let h = 0.5 + 0.5 * sin(th1 * 2.0 - TAU * t / 6.0);
    let mid = mix(s.color.rgb, s.color2.rgb, 0.5);
    var col = mix(s.color.rgb, s.color2.rgb, g);
    col = mix(col, mid, h * 0.5);

    // a soft halo outside it
    let halo = exp(-max(d - r1, 0.0) / 9.0) * 0.30 * (1.0 - a1);

    // the ghost: darker, inset about 11 %, turning the other way
    let th2 = ang + TAU * t / 9.0;
    let r2 = edge(th2, 106.0, t, 2.1);
    let a2 = cover(d, r2) * 0.55;

    let body = col * (1.0 - a2);
    let alpha = max(a1, halo) * s.a.x;
    return vec4<f32>(mix(col, body, a1), alpha);
}
