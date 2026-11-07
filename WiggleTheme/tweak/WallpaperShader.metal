// WallpaperShader.metal — WiggleTheme 0.3.0
// Деформация текстуры обоев экрана блокировки в стиле OriginOS 7.
//
// Два режима (комбинируются):
//   Желе/пружина — затухающая синусоида от импульса акселерометра
//   + «пружинный» сдвиг от наклона телефона (интегрируется на CPU).
//   Водная рябь — радиальный волновой фронт от точки импульса,
//   с затуханием по времени/расстоянию и преломлением (хроматическая дисперсия).
//
// 0.3.0: зона эффекта (uniform zone, мягкие края) + скорости и сила
// преломления вынесены в uniforms (настройки применяются на лету).
//
// Компилируется на устройстве: MTLLibrary из этого исходника.

#include <metal_stdlib>
using namespace metal;

// ВАЖНО: структура должна побайтово совпадать с WGUniforms в Tweak.xm.
struct WGUniforms {
    float4 paramsA; // viewW, viewH, (резерв), intensity
    float4 paramsB; // damping, tiltX, tiltY, mode (0 желе / 1 рябь / 2 оба)
    float4 impulse; // dirX, dirY, magnitude(0..1), age
    float4 ripple;  // centerX, centerY (uv), age, strength(0..1)
    float4 misc;    // hasMask, omega, (резерв), (резерв)
    float4 zone;    // зона эффекта в uv: x0, y0, x1, y1
    float4 fx;      // rippleSpeed, jellySpeed, refraction, zoneEdge
};

struct WGVertOut {
    float4 position [[position]];
    float2 uv;
};

vertex WGVertOut wgVert(uint vid [[vertex_id]]) {
    float2 p[4] = { float2(-1.0, -1.0), float2(1.0, -1.0),
                    float2(-1.0,  1.0), float2(1.0,  1.0) };
    float2 t[4] = { float2(0.0, 0.0), float2(1.0, 0.0),
                    float2(0.0, 1.0), float2(1.0, 1.0) };
    WGVertOut o;
    o.position = float4(p[vid], 0.0, 1.0);
    o.uv = t[vid];
    return o;
}

fragment float4 wgFrag(WGVertOut             in      [[stage_in]],
                       texture2d<float>      wallTex [[texture(0)]],
                       texture2d<float>      maskTex [[texture(1)]],
                       constant WGUniforms & u       [[buffer(0)]])
{
    constexpr sampler smp(mag_filter::linear, min_filter::linear,
                          address::clamp_to_edge);
    float2 uv = in.uv;

    // --- опциональная PNG-маска поверх зоны ---
    float maskA = 1.0;
    if (u.misc.x > 0.5) {
        maskA = maskTex.sample(smp, uv).a;
    }

    float2 disp = float2(0.0);

    // --- ЖЕЛЕ / ПРУЖИНА ---
    if (u.paramsB.w < 0.5 || u.paramsB.w > 1.5) {
        float t    = u.impulse.w;
        float2 dir = u.impulse.xy; // уже нормализован на CPU
        float decay = exp(-u.paramsB.x * t * 2.5);
        float proj  = dot(uv - float2(0.5), dir);
        float wave  = sin(proj * 22.0 - t * u.misc.y * max(u.fx.y, 0.1));
        float amp   = u.impulse.z * u.paramsA.w * decay * wave;
        disp += dir * amp * 0.07;

        // наклон: пружинный сдвиг с CPU
        disp += float2(u.paramsB.y, u.paramsB.z) * 0.05;
    }

    // --- ВОДНАЯ РЯБЬ ---
    if (u.paramsB.w > 0.5) {
        float t = u.ripple.z;
        if (t < 3.5 && u.ripple.w > 0.001) {
            float aspect = u.paramsA.x / max(u.paramsA.y, 1.0);
            float2 d    = (uv - u.ripple.xy) * float2(aspect, 1.0);
            float dist  = length(d) + 1e-5;
            float2 radial = d / dist;
            float front = dist - t * 0.85 * max(u.fx.x, 0.1);
            float env = exp(-front * front / 0.0045)
                      * exp(-t * 1.8)
                      * exp(-dist * 1.1);
            disp += radial * env * sin(front * 55.0)
                  * 0.055 * u.ripple.w * u.paramsA.w;
        }
    }

    // --- гасим у краёв экрана ---
    float2 edge = smoothstep(float2(0.0), float2(0.07), uv)
                * smoothstep(float2(0.0), float2(0.07), 1.0 - uv);
    disp *= edge;

    // --- ЗОНА ЭФФЕКТА (мягкие края; отключается, когда активна нарисованная маска) ---
    if (u.misc.z > 0.5) {
        float2 zmin = u.zone.xy;
        float2 zmax = u.zone.zw;
        float zedge = max(u.fx.w, 0.005);
        float2 zin  = smoothstep(zmin - zedge, zmin + zedge, uv);
        float2 zout = 1.0 - smoothstep(zmax - zedge, zmax + zedge, uv);
        disp *= zin.x * zin.y * zout.x * zout.y;
    }

    disp *= maskA;

    // --- преломление: хроматическая дисперсия, сила = u.fx.z ---
    float refr = clamp(u.fx.z, 0.0, 1.0);
    float2 uvr = uv + disp * (1.0 - 0.10 * refr);
    float2 uvg = uv + disp;
    float2 uvb = uv + disp * (1.0 + 0.10 * refr);
    float4 col;
    col.r = wallTex.sample(smp, uvr).r;
    col.g = wallTex.sample(smp, uvg).g;
    col.b = wallTex.sample(smp, uvb).b;
    col.a = 1.0;
    return col;
}
