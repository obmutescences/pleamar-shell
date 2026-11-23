// Hovered card/tile group shader: 3D perspective tilt toward the pointer, spotlight, and diagonal specular sweep.
//
// s.a.x how hovered it is (0..1)
// s.a.y max tilt in degrees
// s.a.z light sweep progress (0..1)
// s.a.w, s.b.x relative pointer offset across & down (-0.5..0.5)

fn shade(s: Shader) -> vec4<f32> {
    let hot = s.a.x;
    let maxdeg = s.a.y;
    let sweep = s.a.z;
    let p = s.pos;
    let cen = s.size * 0.5;

    let rel = vec2<f32>(s.a.w, s.b.x);
    let k = 0.0174533 * maxdeg * hot;
    let ay = -rel.x * 2.0 * k;
    let ax = rel.y * 2.0 * k;
    let cx = cos(ax);
    let sx = sin(ax);
    let cy = cos(ay);
    let sy = sin(ay);
    let r11 = cy;
    let r21 = sx * sy;
    let r31 = -cx * sy;
    let r12 = 0.0;
    let r22 = cx;
    let r32 = sx;

    let f = s.size.y * 1.7;
    let x = p.x - cen.x;
    let y = p.y - cen.y;
    let a11 = f * r11 - x * r31;
    let a12 = f * r12 - x * r32;
    let a21 = f * r21 - y * r31;
    let a22 = f * r22 - y * r32;
    let b1 = x * f;
    let b2 = y * f;
    let det = a11 * a22 - a12 * a21;
    let u = (b1 * a22 - a12 * b2) / det;
    let v = (a11 * b2 - b1 * a21) / det;
    let c = inside(s, cen + vec2<f32>(u, v));

    let d = length(p - (cen + rel * s.size));
    let spot = exp(-pow(d / (s.size.y * 0.35), 2.0)) * hot;

    let w = (p.x / s.size.x) * 0.75 + (p.y / s.size.y) * 0.25;
    let band = exp(-pow((w - (sweep * 1.7 - 0.35)) / 0.08, 2.0)) * sin(clamp(sweep, 0.0, 1.0) * 3.14159);

    let light = clamp(spot * 0.28 + band * 0.55, 0.0, 1.0);
    let rgb = mix(c.rgb, vec3<f32>(1.0, 1.0, 1.0), light * c.a);
    return vec4<f32>(rgb, c.a);
}
