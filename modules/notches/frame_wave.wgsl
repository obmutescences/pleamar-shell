//  The frame's glass as a disturbed surface.  It runs on the group that holds
//  the frame body, so the edge water and the open drawer's rim move together
//  instead of being separate overlays.
//
//  s.a: bass, panel-present, panel centre x, panel centre y
//  s.b: panel width, panel height, drawer wobble, unused

fn shade(s: Shader) -> vec4<f32> {
    let p = s.pos;
    let t = s.time;
    let bass = clamp(s.a.x, 0.0, 1.0);
    let panel = clamp(s.a.y, 0.0, 1.0);
    let pc = vec2<f32>(s.a.z, s.a.w);
    let half = vec2<f32>(max(s.b.x, 0.0) * 0.5, max(s.b.y, 0.0) * 0.5);
    let wobble = s.b.z;

    //  The screen edge: the same slow travelling wave as the music frame,
    //  fading over about 40 px so the centre is not warped.
    let wt = exp(-p.y / 40.0);
    let wb = exp(-(s.size.y - p.y) / 40.0);
    let wl = exp(-p.x / 40.0);
    let wr = exp(-(s.size.x - p.x) / 40.0);
    let ay = 5.0 * (wt + wb) *
        (0.65 * sin(p.x * 0.0125 - t * 2.0) +
         0.35 * sin(p.x * 0.0053 + t * 1.2 + 1.7));
    let ax = 5.0 * (wl + wr) *
        (0.65 * sin(p.y * 0.0125 - t * 2.0 + 2.0) +
         0.35 * sin(p.y * 0.0053 + t * 1.2 + 4.1));

    //  The open drawer's rim: a soft rounded-rectangle band, so its border
    //  moves with the same water as the screen edge.  The wobble after landing
    //  briefly widens the band.
    let d = abs(p - pc) - half;
    let sd = length(max(d, vec2<f32>(0.0, 0.0))) + min(max(d.x, d.y), 0.0);
    let rim = exp(-abs(sd) / 18.0) * panel;
    let amp = (2.5 + 4.5 * bass + abs(wobble) * 0.01) * rim;
    let bx = amp * sin((p.x + p.y) * 0.035 - t * 4.5);
    let by = amp * cos((p.x - p.y) * 0.031 + t * 3.8);

    return inside(s, vec2<f32>(p.x + ax + bx, p.y + ay + by));
}
