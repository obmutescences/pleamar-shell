// The pencil shading inside a slider / SetPick thumb: the level coloured in with a pencil, in tight columns up and down, the second pass
// fainter and a hair off.
//
// values: xs, xe, sp, h (xs and xe from left edge; middle is box's middle) · jt, fr, stroke, pass (0 strong, 1 faint)
// colors: the pencil's colour

fn ph_sin(deg: f32) -> f32 {
    return sin(deg * 0.017453292519943295);
}

fn ph_turn(fr: f32, speed: f32, phase: f32) -> f32 {
    let f = fr - 360.0 * floor(fr / 360.0);
    let a = f * speed + phase;
    return a - 360.0 * floor(a / 360.0);
}

fn ph_point(j: u32, s: Shader, mid: f32) -> vec2<f32> {
    let xs = s.a.x;
    let xe = s.a.y;
    let sp = s.a.z;
    let h = s.a.w;
    let jt = s.b.x;
    let fr = s.b.y;
    let faint = s.b.w > 0.5;
    let col = f32(j / 2u);
    let half = f32(j % 2u);
    let q = j % 4u;
    let sx = select(-1.0, 1.0, q == 0u || q == 3u);
    let ax0 = select(0.0, 50.0, faint);
    let ay0 = select(0.0, 90.0, faint);
    let fx0 = select(6.0, 21.0, faint);
    let px0 = select(18550.0, 18921.0, faint);
    let ax = ax0 + 67.0 * col + 41.0 * half;
    let ay = ay0 + 29.0 * col + 73.0 * half;
    let fx = 43.0 + f32((u32(fx0) + 7u * j) % 31u);
    let px = px0 + 97.0 * f32(j);
    let x = min(xs + col * sp, xe) + h * 0.1 * sx + h * 0.02 * ph_sin(ax - 360.0 * floor(ax / 360.0)) + jt * ph_sin(ph_turn(fr, fx, px - 360.0 * floor(px / 360.0)));
    let y = mid - h * 0.38 * sx + h * 0.05 * ph_sin(ay - 360.0 * floor(ay / 360.0)) + jt * ph_sin(ph_turn(fr, fx + 5.0, px + 60.0 - 360.0 * floor((px + 60.0) / 360.0)));
    return vec2<f32>(x, y);
}

fn ph_segment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let ab = b - a;
    let t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
    return length(p - a - ab * t);
}

fn shade(s: Shader) -> vec4<f32> {
    let xs = s.a.x;
    let xe = s.a.y;
    let sp = s.a.z;
    let h = s.a.w;
    let jt = s.b.x;
    let w = s.b.z;
    let mid = s.size.y * 0.5;
    let p = s.pos;
    let reach = h * 0.12 + abs(jt) + w;
    var d = 1e9;
    var prev = ph_point(0u, s, mid);
    var prev_base = min(xs, xe);
    for (var j = 1u; j < 176u; j = j + 1u) {
        let base = min(xs + f32(j / 2u) * sp, xe);
        let near = abs(p.x - base) < reach + sp || abs(p.x - prev_base) < reach + sp;
        let here = ph_point(j, s, mid);
        if (near) {
            d = min(d, ph_segment(p, prev, here));
        }
        prev = here;
        prev_base = base;
    }
    let cover = clamp((w * 0.5 - d) * s.scale + 0.5, 0.0, 1.0);
    return vec4<f32>(s.color.rgb, cover);
}
