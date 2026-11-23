// Overview weather card sky: realistic dynamic atmosphere, sun arc, moon phase, stars, two wind-drifting lit cloud layers, fog, storm flash/bolt, rain & snow, with ink-contrast legibility guard.
//
// s.a.x cloud cover (0..1) · s.a.y rain · s.a.z snow · s.a.w fog (0..1) + storm*0.001? -> clean: floor(fog*999) + clamp(storm, 0, 0.999)
// s.b.x clock (seconds, conditional spin) · s.b.y daylight (0 night, 1 day, between twilight)
// s.b.z floor(sunp*1000) + moon_phase (0 new, 0.5 full)
// s.b.w wind in [-1, 1] (signed by wind direction)
// s.color accent · s.color2 ink (text drawn on top)

fn hsh(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = hsh(i);
    let b = hsh(i + vec2<f32>(1.0, 0.0));
    let c = hsh(i + vec2<f32>(0.0, 1.0));
    let d = hsh(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p0: vec2<f32>) -> f32 {
    var p = p0;
    var v = 0.0;
    var a = 0.5;
    for (var i = 0; i < 5; i = i + 1) {
        v = v + a * vnoise(p);
        p = vec2<f32>(p.x * 1.6 + p.y * 1.2, -p.x * 1.2 + p.y * 1.6) + vec2<f32>(3.1, 1.7);
        a = a * 0.5;
    }
    return v;
}

fn luma(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.299, 0.587, 0.114)); }

fn rain_layer(px: vec2<f32>, t: f32, L: f32, slant: f32, amount: f32) -> f32 {
    let cw = 6.0 + L * 5.0;
    let v = 420.0 + L * 260.0;
    let len = 10.0 + L * 9.0;
    var p = px;
    p.x = p.x + p.y * slant;
    let col = floor(p.x / cw);
    let r = hsh(vec2<f32>(col, L * 17.0 + 3.0));
    let r2 = hsh(vec2<f32>(col, L * 17.0 + 9.0));
    if (r2 > amount * (0.55 + L * 0.2)) { return 0.0; }
    let period = 70.0 + r * 90.0;
    let yy = (p.y - t * v * (0.8 + 0.4 * r) - r * 911.0) - period * floor((p.y - t * v * (0.8 + 0.4 * r) - r * 911.0) / period);
    let streak = smoothstep(0.0, len, yy) * step(yy, len);
    let xo = (0.2 + 0.6 * hsh(vec2<f32>(col, 5.0 + L))) * cw;
    let dx = abs(p.x - col * cw - xo);
    return streak * smoothstep(0.6 + L * 0.35, 0.0, dx) * (0.35 + 0.25 * L);
}

fn snow_layer(px: vec2<f32>, t: f32, L: f32, drift: f32) -> f32 {
    let cell = 22.0 + L * 12.0;
    let speed = 14.0 + L * 13.0;
    let p = px + vec2<f32>(-t * drift * 60.0 * (1.0 + L * 0.5), -t * speed);
    let c = floor(p / cell);
    let f = p - c * cell;
    let r = hsh(c + vec2<f32>(L * 31.0, L * 7.0));
    if (r < 0.3) { return 0.0; }
    let ctr = vec2<f32>(0.2 + 0.6 * hsh(c + vec2<f32>(1.3, 7.1)), 0.2 + 0.6 * hsh(c + vec2<f32>(5.7, 2.9))) * cell
        + vec2<f32>(sin(t * (0.7 + r) + r * 6.283) * cell * 0.18, 0.0);
    let rad = 0.9 + L * 0.75 + r * 0.7;
    return smoothstep(rad, rad * 0.25, length(f - ctr)) * (0.55 + 0.2 * L);
}

fn stars(px: vec2<f32>, t: f32, cell: f32, seed: f32) -> f32 {
    let c = floor(px / cell);
    let f = px - c * cell;
    let r = hsh(c + vec2<f32>(seed, seed * 2.0));
    if (r < 0.72) { return 0.0; }
    let ctr = vec2<f32>(0.15 + 0.7 * hsh(c + vec2<f32>(seed + 3.0, 1.0)), 0.15 + 0.7 * hsh(c + vec2<f32>(seed + 8.0, 4.0))) * cell;
    let d = length(f - ctr);
    let tw = 0.55 + 0.45 * sin(t * (1.3 + 3.0 * r) + r * 40.0);
    let size = 0.6 + 1.1 * (r - 0.72) / 0.28;
    return smoothstep(size + 0.8, 0.0, d) * tw;
}

fn shade(s: Shader) -> vec4<f32> {
    let W = s.size.x;
    let H = s.size.y;
    let uv = s.uv;
    let px = s.pos;
    let t = s.b.x;
    let pi = 3.14159265;

    let cl = clamp(s.a.x, 0.0, 1.0);
    let rn = clamp(s.a.y, 0.0, 1.0);
    let sn = clamp(s.a.z, 0.0, 1.0);
    let fg = clamp(floor(s.a.w) / 999.0, 0.0, 1.0);
    let st = clamp(fract(s.a.w), 0.0, 1.0);
    let dl = clamp(s.b.y, 0.0, 1.0);
    let sunp = clamp(floor(s.b.z) / 1000.0, 0.0, 1.0);
    let moon = fract(s.b.z);
    let windq = clamp(abs(s.b.w), 0.0, 1.0);
    let wsign = select(1.0, -1.0, s.b.w < 0.0);
    let drift = wsign * (0.010 + 0.05 * windq);
    let unit = max(H / 260.0, 0.65);

    let par = (s.pointer - s.size * 0.5) / max(s.size, vec2<f32>(1.0)) * s.hovered;

    // ── Sky colour ──
    let golden = clamp(max(dl * (1.0 - smoothstep(0.02, 0.22, min(sunp, 1.0 - sunp))), 1.25 * (1.0 - abs(2.0 * dl - 1.0))), 0.0, 1.0);
    var top = mix(vec3<f32>(0.015, 0.025, 0.08), vec3<f32>(0.16, 0.40, 0.80), dl);
    var hor = mix(vec3<f32>(0.07, 0.11, 0.25), vec3<f32>(0.50, 0.74, 0.95), dl);
    top = mix(top, vec3<f32>(0.30, 0.22, 0.52), golden * 0.8);
    hor = mix(hor, vec3<f32>(1.0, 0.52, 0.30), golden * 0.92);
    let midg = exp(-pow((uv.y - 0.62) * 3.0, 2.0)) * golden;
    let ov = clamp(cl * 0.7 + rn * 0.35 + st * 0.5 + fg * 0.45 + sn * 0.2, 0.0, 1.0);
    top = mix(top, vec3<f32>(luma(top)) * mix(1.0, 0.65, st), ov * 0.8);
    hor = mix(hor, vec3<f32>(luma(hor)) * mix(1.05, 0.7, st), ov * 0.75);
    var sky = mix(top, hor, pow(uv.y, 0.85));
    sky = mix(sky, vec3<f32>(0.92, 0.45, 0.50), midg * 0.35 * (1.0 - ov));

    // ── Sun along daytime arc ──
    let sp = vec2<f32>(mix(0.10, 0.90, sunp) * W, (0.48 - 0.36 * sin(pi * sunp)) * H) - par * 5.0;
    let R = 15.0 * unit;
    let ds = length(px - sp);
    let sunvis = dl * (1.0 - 0.8 * smoothstep(0.35, 1.0, cl)) * (1.0 - 0.9 * st);
    let suncol = mix(vec3<f32>(1.0, 0.93, 0.72), vec3<f32>(1.0, 0.60, 0.30), golden);
    let ang = atan2(px.y - sp.y, px.x - sp.x);
    let rays = pow(0.5 + 0.5 * sin(ang * 11.0 + t * 0.22), 10.0) * 0.5 + pow(0.5 + 0.5 * sin(ang * 7.0 - t * 0.15 + 1.0), 12.0) * 0.4;
    let sglow = exp(-ds / (R * 1.6)) * 0.55 + exp(-ds / (R * 6.0)) * 0.28 + rays * exp(-ds / (R * 4.0)) * 0.45 * (1.0 - cl);
    sky = sky + suncol * sglow * sunvis;
    let sdisc = smoothstep(R + 1.2, R - 1.2, ds) * (0.92 + 0.08 * sin(t * 1.7));
    sky = mix(sky, mix(vec3<f32>(1.0, 0.98, 0.9), suncol, 0.35), sdisc * sunvis);

    // ── Stars & Moon ──
    let nv = (1.0 - dl) * (1.0 - smoothstep(0.3, 0.95, cl)) * (1.0 - st);
    let st_amt = (stars(px + par * 3.0, t, 19.0 * unit, 1.0) + stars(px + par * 2.0 + vec2<f32>(7.0, 3.0), t, 11.0 * unit, 9.0) * 0.6) * (1.0 - 0.8 * uv.y);
    sky = sky + vec3<f32>(0.9, 0.93, 1.0) * st_amt * nv;
    let mp = vec2<f32>(0.80 * W, 0.20 * H) - par * 4.0;
    let Rm = 13.0 * unit;
    let q = (px - mp) / Rm;
    let dm = length(q);
    let mdisc = smoothstep(1.0 + 1.5 / Rm, 1.0 - 1.5 / Rm, dm);
    let yy = clamp(q.y, -1.0, 1.0);
    let edge = sqrt(max(0.0, 1.0 - yy * yy)) * cos(2.0 * pi * moon);
    let lit = select(smoothstep(-edge - 0.06, -edge + 0.06, -q.x), smoothstep(edge - 0.06, edge + 0.06, q.x), moon < 0.5);
    let crater = 1.0 - 0.18 * smoothstep(0.55, 0.75, vnoise(q * 3.0 + vec2<f32>(4.0, 2.0)));
    let mcol = mix(vec3<f32>(0.10, 0.12, 0.20), vec3<f32>(0.96, 0.94, 0.86) * crater, lit);
    let mvis = (1.0 - dl) * (1.0 - 0.75 * smoothstep(0.4, 1.0, cl)) * (1.0 - 0.8 * st);
    sky = sky + vec3<f32>(0.75, 0.8, 1.0) * exp(-max(dm - 1.0, 0.0) * 2.2) * 0.22 * mvis * (0.4 + 0.6 * (1.0 - abs(moon - 0.5) * 2.0));
    sky = mix(sky, mcol, mdisc * mvis);

    // ── Two cloud layers ──
    let sundir = normalize(vec2<f32>(sp.x - px.x, sp.y - px.y) + vec2<f32>(0.001, 0.001));
    var cloudshadow = 0.0;
    for (var l = 0; l < 2; l = l + 1) {
        let L = f32(l);
        let sc = 2.6 + L * 1.9;
        let qc = vec2<f32>(uv.x * W / H, uv.y * 1.35) * sc + vec2<f32>(t * drift * (1.0 + L * 0.7) * sc, L * 13.7) + par * (0.08 + L * 0.06);
        let n = fbm(qc);
        let th = mix(0.80, 0.30, cl) + L * 0.04;
        let dens = smoothstep(th, th + 0.24 - 0.08 * st, n) * mix(1.0, 0.55, uv.y * (1.0 - cl * 0.6));
        let n2 = fbm(qc + sundir * 0.18);
        let lightk = clamp((n - n2) * 4.0 + 0.62, 0.0, 1.0);
        let dayc = mix(vec3<f32>(0.58, 0.62, 0.70), vec3<f32>(1.0, 1.0, 1.0), lightk);
        let stormc = mix(vec3<f32>(0.16, 0.17, 0.22), vec3<f32>(0.42, 0.44, 0.50), lightk);
        let nightc = mix(vec3<f32>(0.06, 0.07, 0.12), vec3<f32>(0.22, 0.25, 0.34), lightk);
        var cc = mix(nightc, mix(dayc, stormc, clamp(st + rn * 0.4, 0.0, 1.0)), dl);
        cc = cc + vec3<f32>(1.0, 0.55, 0.35) * golden * lightk * 0.35;
        cc = cc + suncol * exp(-ds / (R * 3.5)) * sunvis * 0.5;
        let a = dens * (0.92 - L * 0.12);
        sky = mix(sky, cc, a);
        cloudshadow = max(cloudshadow, a);
    }

    // ── Fog ──
    let fb = fbm(vec2<f32>(uv.x * 2.2 + t * 0.025 * wsign, uv.y * 5.0 - t * 0.01));
    let fogk = fg * (0.25 + 0.75 * smoothstep(0.0, 0.9, uv.y)) * (0.45 + 0.75 * fb);
    sky = mix(sky, mix(vec3<f32>(0.20, 0.22, 0.28), vec3<f32>(0.80, 0.82, 0.85), dl), clamp(fogk, 0.0, 0.85));

    // ── Storm lightning ──
    let per = 4.7;
    let seg = floor(t / per);
    let lt = t - seg * per;
    let rr = hsh(vec2<f32>(seg, 3.3));
    let on = step(0.3, rr) * st;
    let flash = (exp(-lt * 10.0) + step(0.13, lt) * exp(-max(lt - 0.13, 0.0) * 13.0) * 0.8) * on;
    let bx = (0.18 + 0.64 * hsh(vec2<f32>(seg, 7.7))) * W + (fbm(vec2<f32>(uv.y * 4.0, seg * 1.3)) - 0.5) * W * 0.22 + (vnoise(vec2<f32>(uv.y * 26.0, seg * 3.1)) - 0.5) * W * 0.035;
    let bend = 0.35 + 0.45 * hsh(vec2<f32>(seg, 9.1));
    let bd = abs(px.x - bx);
    let bolt = (smoothstep(1.6 * unit, 0.0, bd) + exp(-bd / (9.0 * unit)) * 0.5) * step(uv.y, bend) * smoothstep(bend, bend - 0.08, uv.y);
    sky = sky + vec3<f32>(0.75, 0.8, 1.0) * flash * (0.35 + 0.4 * cloudshadow) + vec3<f32>(0.9, 0.92, 1.0) * bolt * flash * 1.4;

    // ── Rain and snow ──
    let slant = -0.18 * drift / 0.06;
    var rainv = 0.0;
    for (var l = 0; l < 3; l = l + 1) { rainv = rainv + rain_layer(px + vec2<f32>(par.x * f32(l) * 4.0, 0.0), t, f32(l), slant, rn); }
    var snowv = 0.0;
    for (var l = 0; l < 3; l = l + 1) { snowv = snowv + snow_layer(px + par * f32(l) * 5.0, t, f32(l), drift); }
    let pcol = mix(vec3<f32>(0.55, 0.62, 0.78), vec3<f32>(0.86, 0.91, 1.0), dl * 0.7 + 0.3);
    sky = mix(sky, pcol, clamp(rainv * rn, 0.0, 0.85));
    sky = mix(sky, vec3<f32>(0.97, 0.98, 1.0), clamp(snowv * sn, 0.0, 0.95));

    // ── Legibility contrast guard against theme ink ──
    let ink = s.color2.rgb;
    let il = luma(ink);
    let lightink = smoothstep(0.42, 0.58, il);
    let L0 = max(luma(sky), 0.001);
    let Ldark = min(L0, 0.14 + L0 * 0.58) * mix(0.76, 1.0, smoothstep(0.0, 0.62, uv.x));
    let Llight = 0.80 + 0.20 * L0;
    let Lt = mix(Llight, Ldark, lightink);
    var glass = mix(vec3<f32>(Lt), sky * (Lt / L0), mix(0.75, 1.0, lightink));
    glass = clamp(glass, vec3<f32>(0.0), vec3<f32>(1.0));
    let pc = mix(s.color2.rgb, s.color.rgb, 0.35);
    glass = mix(glass, pc, clamp(rainv * rn * 1.25, 0.0, 0.8));
    glass = mix(glass, mix(vec3<f32>(1.0), pc, 0.55 * (1.0 - lightink)), clamp(snowv * sn * 1.1, 0.0, 0.95));

    return vec4<f32>(clamp(glass, vec3<f32>(0.0), vec3<f32>(1.0)), 0.88);
}
