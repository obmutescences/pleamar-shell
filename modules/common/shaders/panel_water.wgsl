//  Unified optical water backdrop shader for all Pleamar glass panels.
//  Three visually distinct physical water phenomena behind pure-glass cards:
//    0 · Caustics : sunlit underwater caustic light web + soft expanding rings
//    1 · Ripples  : 3D normal-lit concentric pond ripples + wave interference
//    2 · Droplets : 3D crystal water beads sliding down glass with dew & trails
//
//  s.a: x = style (0 caustics, 1 ripples, 2 droplets)
//       y = strength (0..1)
//       z = speed (0..2, 0 under reduced motion)
//       w = color_mix (0 primary -> 0.5 duet -> 1 secondary)
//  s.b: x = pointer_ripple (0..1)
//       y = detail 1 (caustic scale 0.4..2 | ripple rate 0.2..2 | drop size 0.5..1.8)
//       z = detail 2 (caustic sharp 0..1   | ripple rings 0..1  | drop density 0..1)
//       w = detail 3 (caustic rings 0..1   | ripple gloss 0..1  | drop trails 0..1)
//  s.color = primary, s.color2 = secondary

const TAU: f32 = 6.2831853;

fn pw_hash21(p: vec2<f32>) -> f32 {
    var q = fract(p * vec2<f32>(123.34, 456.21));
    q += dot(q, q + 45.32);
    return fract(q.x * q.y);
}

fn pw_hash22(p: vec2<f32>) -> vec2<f32> {
    let h1 = pw_hash21(p);
    let h2 = pw_hash21(p + vec2<f32>(19.17, 47.63));
    return vec2<f32>(h1, h2);
}

fn pw_tone(c_pri: vec3<f32>, c_sec: vec3<f32>, u: f32, cmix: f32) -> vec3<f32> {
    let shift = (cmix - 0.5) * 1.45;
    return mix(c_pri, c_sec, clamp(u + shift, 0.0, 1.0));
}

//  ── Mode 0 helper: soft ambient expanding ring for Caustics ──────────────
fn pw_caustic_ring(uv: vec2<f32>, aspect: f32, t: f32, seed: f32) -> vec3<f32> {
    let period = 4.6 + pw_hash21(vec2<f32>(seed, 1.9)) * 4.2;
    let phase_raw = t / period + pw_hash21(vec2<f32>(seed, 7.1));
    let cycle = floor(phase_raw);
    let phase = fract(phase_raw);
    let fade_in = smoothstep(0.0, 0.12, phase);
    let fade_out = 1.0 - smoothstep(0.55, 1.0, phase);
    let env = fade_in * fade_out;
    let origin = vec2<f32>(
        0.16 + pw_hash21(vec2<f32>(cycle, seed)) * 0.68,
        0.16 + pw_hash21(vec2<f32>(cycle, seed + 5.7)) * 0.68
    );
    var dp = uv - origin;
    dp.x *= aspect;
    let d = length(dp);
    let front = phase * 0.72;
    let band = exp(-34.0 * (d - front) * (d - front)) * env;
    var dir = vec2<f32>(0.0, 0.0);
    if (d > 0.0005) { dir = dp / d; }
    let osc = sin((d - front) * 38.0 - t * 2.1 + seed * 3.7);
    let crest = pow(max(0.0, osc * 0.5 + 0.5), 2.4) * band;
    return vec3<f32>(dir.x * osc * band * 0.045, dir.y * osc * band * 0.045, crest);
}

//  ── Mode 1 helper: 3D height-field concentric raindrop ripple ────────────
//  Returns vec4(dh/dx, dh/dy, ring_energy, splash_flash)
fn pw_pond_ripple(uv: vec2<f32>, aspect: f32, t: f32, rate: f32, rings: f32, seed: f32) -> vec4<f32> {
    let base_period = (2.6 + pw_hash21(vec2<f32>(seed, 3.1)) * 2.4) / max(rate, 0.2);
    let off = pw_hash21(vec2<f32>(seed, 9.7));
    let raw = t / base_period + off;
    let cycle = floor(raw);
    let phase = fract(raw);

    let origin = vec2<f32>(
        0.08 + pw_hash21(vec2<f32>(cycle, seed * 1.7 + 2.3)) * 0.84,
        0.08 + pw_hash21(vec2<f32>(cycle, seed * 2.9 + 8.1)) * 0.84
    );
    var dp = uv - origin;
    dp.x *= aspect;
    let d = length(dp);
    var dir = vec2<f32>(0.0, 0.0);
    if (d > 0.0004) { dir = dp / d; }

    let fade_in = smoothstep(0.0, 0.06, phase);
    let fade_out = pow(1.0 - phase, 1.45);
    let front = phase * mix(0.46, 0.68, rings);

    //  Wave packet: crisp concentric ripples radiating from origin
    let freq = mix(36.0, 76.0, rings);
    let env_k = mix(155.0, 26.0, rings);
    let delta = d - front;
    let env = exp(-env_k * delta * delta) * fade_in * fade_out / (1.0 + d * 2.4);
    let theta = delta * freq;
    let dh_dd = (cos(theta) * freq - sin(theta) * (2.0 * env_k * delta)) * env * 0.014;
    let energy = abs(sin(theta)) * env;

    //  Tiny crisp splash glint at moment of impact
    let splash_t = exp(-phase * 26.0);
    let splash = exp(-d * d * 2600.0) * splash_t;
    return vec4<f32>(dir.x * dh_dd, dir.y * dh_dd, energy, splash);
}

//  ── Mode 2 helper: one parallax grid of 3D sliding crystal droplets ──────
//  Returns vec4(nx, ny, bead_alpha, trail_and_shadow_packed)
//  Packed in w: positive = wet streak brightness, shadow computed separately
struct DropSample {
    normal: vec2<f32>,
    mask: f32,
    radial: f32,
    shadow: f32,
    streak: f32,
    tint_u: f32,
}

fn pw_drop_layer(uv: vec2<f32>, aspect: f32, t: f32, cols: f32, density: f32, trail_amt: f32, seed: f32) -> DropSample {
    var out: DropSample;
    out.normal = vec2<f32>(0.0, 0.0);
    out.mask = 0.0;
    out.radial = 0.0;
    out.shadow = 0.0;
    out.streak = 0.0;
    out.tint_u = 0.5;

    //  Tall cells so each bead glides smoothly vertically down the glass
    let cell_aspect = 2.35;
    let grid = vec2<f32>(cols * aspect, cols / cell_aspect);
    let st_raw = uv * grid;
    let col_id = floor(st_raw.x);
    let col_rnd = pw_hash22(vec2<f32>(col_id + seed * 13.7, seed * 5.3));

    //  Stagger vertical cell origin per column & slowly drift grid downward
    let col_speed = (0.11 + 0.14 * col_rnd.x) * (0.75 + 0.5 * col_rnd.y);
    let y_shift = col_rnd.y * 17.3 - t * col_speed;
    let st_shifted = vec2<f32>(st_raw.x, st_raw.y + y_shift);
    let cell_id = floor(st_shifted);
    let f = fract(st_shifted) - vec2<f32>(0.5, 0.5);

    let rnd = pw_hash22(cell_id + vec2<f32>(seed * 31.1, seed * 17.9));
    let rnd2 = pw_hash21(cell_id * 1.37 + vec2<f32>(seed * 9.3, 4.1));
    out.tint_u = rnd2;

    //  Density gate: leave calm clean glass around beads
    let keep_prob = clamp(0.14 + density * 0.78, 0.0, 0.94);
    if (rnd.x > keep_prob) {
        return out;
    }

    //  Stick-slip downward drop movement inside cell (`f.y` goes -0.5 top -> +0.5 bottom)
    let phase = fract(t * (0.20 + 0.22 * rnd.y) + rnd2 * 7.0);
    //  Monotonic stick-slip curve: pauses briefly then slips cleanly downward
    let slip = phase + 0.065 * sin(phase * TAU * 2.0);
    let drop_y = mix(-0.36, 0.36, clamp(slip, 0.0, 1.0));
    let edge_fade = smoothstep(0.0, 0.12, phase) * (1.0 - smoothstep(0.84, 1.0, phase));

    //  Gentle organic horizontal weave as droplet avoids glass micro-texture
    let weave_w = (cell_id.y + drop_y + 0.5) * 4.2 + col_rnd.x * TAU;
    let drop_x = (rnd.y - 0.5) * 0.44 + sin(weave_w) * 0.085;

    //  Main teardrop in pixel-aspect-corrected local space
    let dp_raw = vec2<f32>(f.x - drop_x, (f.y - drop_y) * cell_aspect);
    //  Slightly elongated teardrop silhouette (tapers gently at upper tail)
    let taper = 1.0 + clamp(-dp_raw.y * 0.52, -0.14, 0.28);
    let dp = vec2<f32>(dp_raw.x * taper, dp_raw.y * 0.78);
    let rad = (0.145 + 0.080 * rnd2) * (0.72 + 0.28 * edge_fade);
    let d_main = length(dp) / max(rad, 0.001);
    let m_main = (1.0 - smoothstep(0.84, 1.02, d_main)) * edge_fade;

    //  Soft contact shadow just below-right of the main bead
    let sh_dp = vec2<f32>(dp_raw.x - rad * 0.14, (dp_raw.y - rad * 0.28) * 0.82);
    let sh_main = (1.0 - smoothstep(0.65, 1.38, length(sh_dp) / max(rad, 0.001))) * edge_fade * (1.0 - m_main * 0.85);

    //  Trailing micro-beads & wet cleared streak left ABOVE the sliding drop (`f.y < drop_y`)
    var m_trail = 0.0;
    var n_trail = vec2<f32>(0.0, 0.0);
    var r_trail = 0.0;
    var sh_trail = 0.0;
    var streak = 0.0;

    if (trail_amt > 0.01 && f.y < drop_y) {
        let behind_dist = clamp((drop_y - f.y) / 0.72, 0.0, 1.0);
        let trail_fade = (1.0 - smoothstep(0.0, 1.0, behind_dist)) * edge_fade * trail_amt;
        let streak_dx = abs(f.x - drop_x);
        //  Subtle glossy wet vertical smear where the bead cleared the pane
        streak = exp(-streak_dx * streak_dx / max(rad * rad * 0.42, 0.002)) * trail_fade * smoothstep(0.02, 0.10, behind_dist);

        //  Micro-beads left behind along the trail track
        let sub_n = 7.0;
        let sub_y_coord = (f.y + 0.5) * sub_n;
        let sub_id = floor(sub_y_coord);
        let sub_fy = fract(sub_y_coord) - 0.5;
        let sub_rnd = pw_hash21(vec2<f32>(cell_id.x * 11.3 + sub_id, cell_id.y * 7.7 + seed));
        if (sub_rnd > 0.32) {
            let sub_x = drop_x + (sub_rnd - 0.65) * 0.08;
            let t_dp = vec2<f32>(f.x - sub_x, sub_fy * (cell_aspect / sub_n));
            let t_rad = rad * (0.24 + 0.22 * sub_rnd) * (0.45 + 0.55 * trail_fade);
            let d_t = length(t_dp) / max(t_rad, 0.001);
            m_trail = (1.0 - smoothstep(0.76, 1.02, d_t)) * trail_fade;
            if (m_trail > 0.01) {
                n_trail = t_dp / max(t_rad, 0.001);
                r_trail = clamp(d_t, 0.0, 1.0);
            }
            let t_sh = vec2<f32>(t_dp.x - t_rad * 0.12, t_dp.y - t_rad * 0.24);
            sh_trail = (1.0 - smoothstep(0.60, 1.35, length(t_sh) / max(t_rad, 0.001))) * trail_fade * 0.55;
        }
    }

    if (m_main >= m_trail) {
        out.mask = m_main;
        out.normal = dp / max(rad, 0.001);
        out.radial = clamp(d_main, 0.0, 1.0);
    } else {
        out.mask = m_trail;
        out.normal = n_trail;
        out.radial = r_trail;
    }
    out.shadow = max(sh_main, sh_trail);
    out.streak = streak;
    return out;
}

//  ── Mode 2 helper: fine static condensation dew layer ────────────────────
fn pw_dew_layer(uv: vec2<f32>, aspect: f32, cols: f32, density: f32, seed: f32) -> DropSample {
    var out: DropSample;
    out.normal = vec2<f32>(0.0, 0.0);
    out.mask = 0.0;
    out.radial = 0.0;
    out.shadow = 0.0;
    out.streak = 0.0;
    out.tint_u = 0.5;

    let grid = vec2<f32>(cols * aspect, cols);
    let st = uv * grid;
    let id = floor(st);
    let f = fract(st) - vec2<f32>(0.5, 0.5);
    let rnd = pw_hash22(id + vec2<f32>(seed * 23.1, seed * 41.7));
    let rnd2 = pw_hash21(id + vec2<f32>(7.3, seed * 11.9));
    out.tint_u = rnd2;

    if (rnd.x > clamp(density * 0.72, 0.0, 0.75)) {
        return out;
    }
    let pos = (rnd - vec2<f32>(0.5, 0.5)) * 0.56;
    let dp = f - pos;
    let rad = 0.11 + 0.10 * rnd2;
    let d = length(dp) / rad;
    out.mask = 1.0 - smoothstep(0.75, 1.02, d);
    out.normal = dp / rad;
    out.radial = clamp(d, 0.0, 1.0);
    let sh_dp = dp - vec2<f32>(rad * 0.14, rad * 0.24);
    out.shadow = (1.0 - smoothstep(0.65, 1.35, length(sh_dp) / rad)) * 0.45 * (1.0 - out.mask * 0.8);
    return out;
}

fn shade(s: Shader) -> vec4<f32> {
    let strength = clamp(s.a.y, 0.0, 1.0);
    if (strength <= 0.002) {
        return vec4<f32>(0.0, 0.0, 0.0, 0.0);
    }

    let style = s.a.x;
    let speed = clamp(s.a.z, 0.0, 2.0);
    let cmix = clamp(s.a.w, 0.0, 1.0);
    let ptr_amt = clamp(s.b.x, 0.0, 1.0);

    let uv = s.uv;
    let aspect = s.size.x / max(s.size.y, 1.0);
    let t = s.time * speed;
    let c_pri = s.color.rgb;
    let c_sec = s.color2.rgb;

    //  Shared cursor distance & ripple data
    var ptr_dp = vec2<f32>(0.0, 0.0);
    var ptr_d = 10.0;
    var ptr_disp = vec2<f32>(0.0, 0.0);
    var ptr_glint = 0.0;
    var ptr_halo = 0.0;
    if (ptr_amt > 0.005 && s.hovered > 0.01) {
        ptr_dp = (s.pos - s.pointer) / max(s.size.y, 1.0);
        ptr_d = length(ptr_dp);
        let fall = exp(-ptr_d * 4.4) * s.hovered * ptr_amt;
        var dir = vec2<f32>(0.0, 0.0);
        if (ptr_d > 0.0005) { dir = ptr_dp / ptr_d; }
        let wave_p = sin(ptr_d * 32.0 - t * 4.4);
        ptr_disp = dir * wave_p * fall * 0.14;
        ptr_glint = pow(max(0.0, wave_p * 0.5 + 0.5), 2.6) * fall;
        ptr_halo = exp(-ptr_d * ptr_d * 14.0) * s.hovered * ptr_amt;
    }

    var col = vec3<f32>(0.0, 0.0, 0.0);
    var alpha = 0.0;

    if (style < 0.5) {
        //  ── MODE 0 · CAUSTICS & GENTLE RIPPLES ──────────────────────────
        let scale = clamp(s.b.y, 0.4, 2.0);
        let sharp = clamp(s.b.z, 0.0, 1.0);
        let ring_amt = clamp(s.b.w, 0.0, 1.0);

        let r1 = pw_caustic_ring(uv, aspect, t, 1.3);
        let r2 = pw_caustic_ring(uv, aspect, t, 3.7);
        let r3 = pw_caustic_ring(uv, aspect, t, 6.9);
        let ring_disp = (r1.xy + r2.xy + r3.xy) * ring_amt * 2.8;
        let ring_crest = clamp(r1.z + r2.z + r3.z, 0.0, 1.4) * ring_amt;

        let p = (uv - vec2<f32>(0.5, 0.5)) * vec2<f32>(aspect, 1.0) * (2.6 * scale)
              + ptr_disp * 1.6 + ring_disp * 2.2;

        let w1 = p + vec2<f32>(
            sin(p.y * 1.45 + t * 0.62) * 0.44 + cos(p.x * 0.85 - t * 0.35) * 0.22,
            cos(p.x * 1.35 - t * 0.54) * 0.44 + sin(p.y * 0.90 + t * 0.41) * 0.22
        );
        let p_rot = vec2<f32>(p.x * 0.77 - p.y * 0.64, p.x * 0.64 + p.y * 0.77) * 1.24;
        let w2 = p_rot + vec2<f32>(
            cos(p_rot.y * 1.55 - t * 0.68 + 1.3) * 0.40,
            sin(p_rot.x * 1.45 + t * 0.58 + 2.1) * 0.40
        );

        let n1 = abs(sin(w1.x * 2.05 + t * 0.48) + cos(w1.y * 2.05 - t * 0.42));
        let n2 = abs(sin(w2.x * 2.20 - t * 0.54 + 0.9) + cos(w2.y * 2.15 + t * 0.46 + 1.7));

        let ridge1 = 1.0 - clamp(n1 * 0.54, 0.0, 1.0);
        let ridge2 = 1.0 - clamp(n2 * 0.54, 0.0, 1.0);
        let expo = mix(1.9, 6.8, sharp);
        let c_a = pow(ridge1, expo);
        let c_b = pow(ridge2, expo);
        let c_cross = pow(ridge1 * ridge2, expo * 0.72);
        let caustic = clamp(c_a * 0.56 + c_b * 0.48 + c_cross * 0.62, 0.0, 1.35);

        let tide = 0.5 + 0.5 * sin(uv.x * 3.4 - uv.y * 2.2 + t * 0.38);
        let base_wash = 0.14 + 0.10 * tide;

        let hue_u = clamp(uv.x * 0.55 + uv.y * 0.25 + (c_b - c_a) * 0.45, 0.0, 1.0);
        let base_col = pw_tone(c_pri, c_sec, hue_u, cmix);
        let ring_col = pw_tone(c_pri, c_sec, clamp(0.75 - hue_u * 0.4, 0.0, 1.0), cmix);

        let spec = clamp(caustic * (0.42 + 0.28 * sharp) + ring_crest * 0.42 + ptr_glint * 0.50, 0.0, 0.85);
        col = mix(base_col, ring_col, clamp(ring_crest * 0.65, 0.0, 0.7));
        col = mix(col, vec3<f32>(1.0, 1.0, 1.0), spec * 0.54);

        let vig = 0.76 + 0.24 * (1.0 - smoothstep(0.25, 0.92, length(uv - vec2<f32>(0.5, 0.5))));
        let energy = base_wash + caustic * (0.44 + 0.16 * sharp) + ring_crest * 0.34 + ptr_glint * 0.32 + ptr_halo * 0.14;
        alpha = clamp(energy * vig * strength * 0.58, 0.0, 0.82);

    } else if (style < 1.5) {
        //  ── MODE 1 · 3D CONCENTRIC POND RIPPLES & INTERFERENCE ──────────
        let rate = clamp(s.b.y, 0.2, 2.0);
        let rings = clamp(s.b.z, 0.0, 1.0);
        let gloss = clamp(s.b.w, 0.0, 1.0);

        //  7 independent asynchronous raindrop wave trains interfering in 3D height field
        let w1 = pw_pond_ripple(uv, aspect, t, rate, rings, 1.1);
        let w2 = pw_pond_ripple(uv, aspect, t, rate, rings, 2.7);
        let w3 = pw_pond_ripple(uv, aspect, t, rate, rings, 4.3);
        let w4 = pw_pond_ripple(uv, aspect, t, rate, rings, 6.1);
        let w5 = pw_pond_ripple(uv, aspect, t, rate, rings, 8.9);
        let w6 = pw_pond_ripple(uv, aspect, t, rate, rings, 11.3);
        let w7 = pw_pond_ripple(uv, aspect, t, rate, rings, 14.7);

        //  Higher density activates more simultaneous concentric ripples cleanly
        let g4 = smoothstep(0.35, 0.85, rate);
        let g6 = smoothstep(0.75, 1.45, rate);

        var grad = w1.xy + w2.xy + w3.xy + (w4.xy + w5.xy) * g4 + (w6.xy + w7.xy) * g6;
        var energy = w1.z + w2.z + w3.z + (w4.z + w5.z) * g4 + (w6.z + w7.z) * g6;
        let splash = w1.w + w2.w + w3.w + (w4.w + w5.w) * g4 + (w6.w + w7.w) * g6;

        //  Interactive pointer emits physical concentric interference ripples too!
        if (ptr_amt > 0.005 && s.hovered > 0.01) {
            let p_fall = exp(-ptr_d * 5.2) * s.hovered * ptr_amt;
            var p_dir = vec2<f32>(0.0, 0.0);
            if (ptr_d > 0.0004) { p_dir = ptr_dp / ptr_d; }
            let p_dh = cos(ptr_d * 46.0 - t * 5.5) * p_fall * 0.72;
            grad += p_dir * p_dh;
            energy += abs(sin(ptr_d * 46.0 - t * 5.5)) * p_fall * 0.85;
        }

        //  Reconstruct 3D water surface normal from summed height-field gradient
        let slope_scale = mix(1.35, 2.65, gloss);
        let n_vec = normalize(vec3<f32>(-grad.x * slope_scale, -grad.y * slope_scale, 1.0));
        let slope_mag = clamp(length(grad) * 1.45, 0.0, 1.4);

        //  Two-sided opposing sky & rim lights reveal front/back ring crescents in 3D
        let l_pri = normalize(vec3<f32>(-0.58, -0.68, 0.45));
        let l_sec = normalize(vec3<f32>(0.62, 0.54, 0.57));
        let v_dir = vec3<f32>(0.0, 0.0, 1.0);
        let h_pri = normalize(l_pri + v_dir);
        let h_sec = normalize(l_sec + v_dir);

        let exp_s = mix(10.0, 44.0, gloss);
        let sp_pri = pow(max(0.0, dot(n_vec, h_pri)), exp_s) * smoothstep(0.04, 0.35, slope_mag);
        let sp_sec = pow(max(0.0, dot(n_vec, h_sec)), exp_s * 0.85) * smoothstep(0.04, 0.35, slope_mag);

        //  Directional facing selects primary vs secondary tint across opposite ring arcs
        let facing = clamp(0.5 + (grad.x * 0.7 + grad.y * 0.7) * 1.15, 0.0, 1.0);
        let ring_col = pw_tone(c_pri, c_sec, facing, cmix);
        let rim_tint = mix(c_pri, c_sec, clamp(sp_sec / max(sp_pri + sp_sec, 0.001), 0.0, 1.0));

        //  Crisp white specular crescents + splash pinpoint sparkle
        let glint = clamp((sp_pri + sp_sec) * (0.75 + 0.65 * gloss) + splash * 1.4, 0.0, 1.25);
        col = mix(ring_col, rim_tint, clamp((sp_pri + sp_sec) * 0.6, 0.0, 0.7));
        col = mix(col, vec3<f32>(1.0, 1.0, 1.0), clamp(glint * 0.68, 0.0, 0.92));

        //  Serene dark mirror water between rings; bright 3D arcs where ripples interfere
        let mirror_bed = 0.035;
        let ring_vis = slope_mag * (0.34 + 0.16 * gloss) + energy * 0.24 + glint * 0.58 + splash * 0.55;
        alpha = clamp((mirror_bed + ring_vis) * strength * 0.86, 0.0, 0.90);

    } else {
        //  ── MODE 2 · 3D CRYSTAL RAIN DROPLETS & CONDENSATION ON GLASS ───
        let size_k = clamp(s.b.y, 0.5, 1.8);
        let density = clamp(s.b.z, 0.0, 1.0);
        let trail_amt = clamp(s.b.w, 0.0, 1.0);

        //  Larger size_k => fewer columns => bigger hero droplets
        let base_cols = 10.5 / size_k;

        //  Two parallax falling bead layers + one fine static condensation dew layer
        let d_big = pw_drop_layer(uv, aspect, t * 0.95, base_cols, density, trail_amt, 1.7);
        let d_mid = pw_drop_layer(uv + vec2<f32>(0.37, 0.19), aspect, t * 0.72, base_cols * 1.65, density * 0.92, trail_amt * 0.78, 5.3);
        let d_dew = pw_dew_layer(uv + vec2<f32>(0.13, 0.61), aspect, base_cols * 3.1, density * 0.80, 9.1);

        //  Pick topmost visible droplet bead (big > mid > static dew)
        var mask = 0.0;
        var n2 = vec2<f32>(0.0, 0.0);
        var rad_u = 0.0;
        var tint_u = 0.5;
        var is_hero = 0.0;

        if (d_big.mask > 0.05) {
            mask = d_big.mask;
            n2 = d_big.normal;
            rad_u = d_big.radial;
            tint_u = d_big.tint_u;
            is_hero = 1.0;
        } else if (d_mid.mask > 0.05) {
            mask = d_mid.mask;
            n2 = d_mid.normal;
            rad_u = d_mid.radial;
            tint_u = d_mid.tint_u;
            is_hero = 0.75;
        } else if (d_dew.mask > 0.05) {
            mask = d_dew.mask * 0.65;
            n2 = d_dew.normal;
            rad_u = d_dew.radial;
            tint_u = d_dew.tint_u;
            is_hero = 0.42;
        }

        let shadow = clamp(max(d_big.shadow, max(d_mid.shadow * 0.78, d_dew.shadow * 0.45)), 0.0, 1.0);
        let streak = clamp(d_big.streak * 0.85 + d_mid.streak * 0.50, 0.0, 1.0);

        //  3D hemispherical crystal-water lens optics:
        //  Clear hollow center, sharp white upper-left glint, bright bottom lens caustic & Fresnel rim
        let nz = sqrt(max(0.02, 1.0 - min(dot(n2, n2), 0.98)));
        let n3 = normalize(vec3<f32>(n2.x, n2.y, nz));

        var l_spec = normalize(vec3<f32>(-0.52, -0.66, 0.54));
        if (ptr_amt > 0.005 && s.hovered > 0.01) {
            let p_shift = clamp(-ptr_dp * 1.4, vec2<f32>(-0.6, -0.6), vec2<f32>(0.6, 0.6)) * s.hovered * ptr_amt;
            l_spec = normalize(vec3<f32>(-0.52 + p_shift.x, -0.66 + p_shift.y, 0.54));
        }
        let h_spec = normalize(l_spec + vec3<f32>(0.0, 0.0, 1.0));
        let spec_dot = pow(max(0.0, dot(n3, h_spec)), 34.0);
        let spec_broad = pow(max(0.0, dot(n3, h_spec)), 7.0) * 0.24;

        let l_caustic = normalize(vec3<f32>(0.42, 0.76, 0.48));
        let bead_caustic = pow(max(0.0, dot(n3, l_caustic)), 2.6) * smoothstep(0.32, 0.94, rad_u);
        let fresnel = pow(clamp(rad_u, 0.0, 1.0), 3.4);

        let drop_hue = pw_tone(c_pri, c_sec, clamp(tint_u * 0.65 + uv.x * 0.35, 0.0, 1.0), cmix);
        let caustic_hue = pw_tone(c_pri, c_sec, clamp(1.0 - tint_u * 0.65, 0.0, 1.0), cmix);

        var bead_col = mix(drop_hue * 0.68, caustic_hue * 1.18, bead_caustic * 0.82);
        bead_col = mix(bead_col, vec3<f32>(1.0, 1.0, 1.0), clamp(spec_dot * 0.98 + spec_broad * 0.36 + fresnel * 0.52 + bead_caustic * 0.32, 0.0, 0.96));

        //  Hollow crystal bead alpha: crystal-clear center so text reads cleanly, bright rim & glint
        let bead_a = mask * (0.14 + 0.56 * fresnel + 0.60 * bead_caustic + 0.96 * spec_dot + 0.18 * spec_broad) * (0.62 + 0.38 * is_hero);

        let streak_col = mix(pw_tone(c_pri, c_sec, uv.x, cmix), vec3<f32>(1.0, 1.0, 1.0), 0.38);
        let streak_a = streak * 0.20 * (1.0 - mask);
        let mist_bg = 0.02 + 0.03 * density;
        let ptr_boost = ptr_halo * 0.14;

        let bright_a = clamp(bead_a + streak_a + mist_bg + ptr_boost, 0.0, 1.0);
        let shadow_a = shadow * 0.36 * (1.0 - mask);
        let total_a = clamp(bright_a + shadow_a, 0.0, 1.0);

        let bright_col = mix(streak_col, bead_col, clamp(bead_a / max(bead_a + streak_a + mist_bg + 0.001, 0.001), 0.0, 1.0));
        col = bright_col * (bright_a / max(total_a, 0.001));
        alpha = clamp(total_a * strength * 0.88, 0.0, 0.90);
    }

    //  Subtle triangular dither to keep dark glass gradients silky smooth
    let q = floor(s.pos * s.scale);
    let n = pw_hash21(q) + pw_hash21(q + vec2<f32>(17.31, 5.17)) - 1.0;
    col = clamp(col + vec3<f32>(n / 255.0), vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(1.0, 1.0, 1.0));
    return vec4<f32>(col, alpha);
}
