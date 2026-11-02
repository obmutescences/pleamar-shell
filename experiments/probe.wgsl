fn shade(s: Shader) -> vec4<f32> {
    let pulse = 0.5 + 0.5 * sin(s.time * 3.0);
    return vec4<f32>(0.55, 0.96, 0.87, 0.6 + 0.4 * pulse);
}
