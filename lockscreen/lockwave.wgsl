// The lock screen's wallpaper, in one pass: the entrance ring, then three
// randomised surface ripples that keep cycling for as long as the lock is up.
//
// s.a.x entrance progress (0..1) · s.a.y peak displacement, in texture units
// s.a.z rings across the surface · s.a.w how much of the light is left after the
// darkening (58 % black over it: 0.42)
//
// Once the entrance reaches 1 its envelope is exactly zero, so the resting
// image is pixel-exact between pulses. The random pulses never stop while the
// scene is painting; their timing comes from s.time, not from a timer.

const TAU: f32 = 6.2831853;

fn hash21(p: vec2<f32>) -> f32 {
    var q = fract(p * vec2<f32>(123.34, 456.21));
    q += dot(q, q + 45.32);
    return fract(q.x * q.y);
}

fn ripple(uv: vec2<f32>, aspect: f32, t: f32, seed: f32) -> vec2<f32> {
    let period = 4.2 + hash21(vec2<f32>(seed, 1.7)) * 4.4;
    let cycle = floor(t / period + hash21(vec2<f32>(seed, 8.3)));
    let phase = fract(t / period + hash21(vec2<f32>(seed, 8.3)));
    let fade_in = smoothstep(0.0, 0.10, phase);
    let fade_out = 1.0 - smoothstep(0.62, 1.0, phase);
    let origin = vec2<f32>(
        0.5 + (hash21(vec2<f32>(cycle, seed)) - 0.5) * 0.30,
        0.5 + (hash21(vec2<f32>(cycle, seed + 7.3)) - 0.5) * 0.24
    );
    var p = uv - origin;
    p.x *= aspect;
    let d = length(p);
    let front = phase * 0.82;
    let band = exp(-30.0 * (d - front) * (d - front));
    var dir = vec2<f32>(0.0, 0.0);
    if (d > 0.0001) { dir = p / d; }
    dir.x = dir.x / aspect;
    let amp = (0.010 + 0.010 * hash21(vec2<f32>(cycle, seed + 2.0))) * band * fade_in * fade_out;
    return dir * sin((d - front) * 42.0 - t * 2.4 + seed * 5.1) * amp;
}

fn shade(s: Shader) -> vec4<f32> {
    let aspect = s.size.x / s.size.y;
    let uv = s.uv;
    var centred = uv - vec2<f32>(0.5, 0.5);
    centred.x = centred.x * aspect;
    let dist = length(centred);

    // The entrance: one ring leaving the centre and settling.
    let front = s.a.x * 0.85;
    let band = exp(-28.0 * (dist - front) * (dist - front));
    let decay = 1.0 - smoothstep(0.55, 1.0, s.a.x);
    let envelope = band * decay;
    let entry_phase = (dist - front) * s.a.z * TAU - s.time * 3.6;
    var offset = vec2<f32>(0.0, 0.0);
    var dir = vec2<f32>(0.0, 0.0);
    if (dist > 0.0001) { dir = centred / dist; }
    dir.x = dir.x / aspect;
    offset += dir * sin(entry_phase) * s.a.y * envelope;

    // Always-on water: a shallow ambient tide plus three independent random
    // ripples, staggered so there is no quiet gap between them.
    offset += vec2<f32>(
        sin(uv.y * 8.0 + s.time * 0.45),
        cos(uv.x * 6.5 + s.time * 0.34)
    ) * 0.0012;
    offset += ripple(uv, aspect, s.time, 1.0);
    offset += ripple(uv, aspect, s.time, 2.7);
    offset += ripple(uv, aspect, s.time, 5.9);

    var sample_uv = uv + offset;
    // A sample pushed outside the image would smear an edge pixel: mirror it back instead.
    sample_uv = abs(sample_uv);
    if (sample_uv.x > 1.0) { sample_uv.x = 2.0 - sample_uv.x; }
    if (sample_uv.y > 1.0) { sample_uv.y = 2.0 - sample_uv.y; }
    let c = inside(s, sample_uv * s.size);

    // A little chromatic separation on the ring's crest, so the glass reads as
    // a surface rather than a moving bitmap.
    let crest = exp(-55.0 * (dist - front) * (dist - front)) * decay;
    let chroma = dir * crest * 0.0018;

    // Triangular noise, plus and minus one level, from two independent draws per pixel.
    let q = floor(s.pos * s.scale);
    let n = hash21(q) + hash21(q + vec2<f32>(17.31, 5.17)) - 1.0;
    return vec4<f32>(c.rgb * s.a.w + vec3<f32>(n / 255.0), c.a);
}
