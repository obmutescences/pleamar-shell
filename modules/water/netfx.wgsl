//  Live overlay for the Overview network history well.  The history bars are
//  scene primitives updated once a second; this shader adds the continuous
//  sweep and right-edge pulse that tell the eye the monitor is still running
//  even when the link is almost idle.
//
//  values: a.x = online (0/1).  The graph itself supplies the real samples.

fn sd_round_box(p: vec2<f32>, half_size: vec2<f32>, radius: f32) -> f32 {
    let q = abs(p) - (half_size - vec2<f32>(radius, radius));
    return length(max(q, vec2<f32>(0.0, 0.0)))
        + min(max(q.x, q.y), 0.0) - radius;
}

fn shade(s: Shader) -> vec4<f32> {
    if (s.a.x < 0.5) {
        return vec4<f32>(0.0, 0.0, 0.0, 0.0);
    }

    let p = (s.uv - vec2<f32>(0.5, 0.5)) * s.size;
    let dist = sd_round_box(p, s.size * 0.5, 10.0);
    let mask = 1.0 - smoothstep(-1.2, 0.6, dist);
    if (mask <= 0.001) {
        return vec4<f32>(0.0, 0.0, 0.0, 0.0);
    }

    //  A soft scan travels left to right and re-enters from the left.  The
    //  second, wider trail makes the motion visible on dim displays without
    //  turning the chart into a light bar.
    let phase = fract(s.time * 0.17);
    let beam = exp(-abs(s.uv.x - phase) * 34.0);
    let trail = exp(-abs(s.uv.x - phase + 0.08) * 9.0);
    let beam_alpha = beam * 0.16 + trail * 0.035;

    //  The live edge answers the once-a-second sample updates with a slow
    //  breathing pulse.
    let pulse = 0.5 + 0.5 * sin(s.time * 3.2);
    let edge = exp(-abs(s.uv.x - 0.965) * 44.0);
    let edge_alpha = edge * (0.18 + 0.22 * pulse);

    //  A very quiet horizontal shimmer, so even a flat history reads as a
    //  running instrument rather than a painted line.
    let shimmer = exp(-abs(s.uv.y - 0.5) * 22.0)
        * (0.35 + 0.25 * sin(s.uv.x * 18.0 + s.time * 1.7));
    let shimmer_alpha = shimmer * 0.025;

    var color = s.color.rgb;
    color = mix(color, s.color2.rgb, smoothstep(0.55, 1.0, s.uv.x) * 0.55);
    color = mix(color, vec3<f32>(1.0, 1.0, 1.0), edge * 0.35);

    let alpha = mask * clamp(beam_alpha + edge_alpha + shimmer_alpha, 0.0, 0.46);
    return vec4<f32>(color, alpha);
}
