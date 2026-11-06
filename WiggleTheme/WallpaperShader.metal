// WallpaperShader.metal — WiggleTheme
// Деформация текстуры обоев экрана блокировки в стиле OriginOS 7.
//
// Два режима (комбинируются):
//   Желе/пружина — затухающая синусоида, амплитуда = последний импульс
//   акселерометра, направление = вектор импульса; поверх — «пружинный»
//   сдвиг от наклона телефона (интегрируется на CPU).
//   Водная рябь — радиальный волновой фронт, расширяющийся от точки
//   импульса, с затуханием по времени и расстоянию + преломление
//   (лёгкая хроматическая дисперсия).
//
// Компилируется на устройстве: MTLLibrary из этого исходника
// (путь: /var/jb/Library/Application Support/WiggleTheme/WallpaperShader.metal).

#include <metal_stdlib>
using namespace metal;

// ВАЖНО: структура должна побайтово совпадать с WGUniforms в Tweak.xm.
struct WGUniforms {
    float4 paramsA; // viewW, viewH, (резерв), intensity
    float4 paramsB; // damping, tiltX, tiltY, mode (0 желе / 1 рябь / 2 оба)
    float4 impulse; // dirX, dirY, magnitude(0..1), age
    float4 ripple;  // centerX, centerY (uv), age, strength(0..1)
    float4 misc;    // hasMask, omega, (резерв), (резерв)
};

struct WGVertOut {
    float4 position [[position]];
    float2 uv;
};

// Полноэкранный треугольный веер из 4 вершин (vertex_id 0..3).
vertex WGVertOut wgVert(uint vid [[vertex_id]]) {
    float2 p[4] = { float2(-1.0, -1.0), float2(1.0, -1.0),
                    float2(-1.0,  1.0), float2(1.0,  1.0) };
    // uv (0,0) — левый НИЗ, совпадает с ориентацией текстуры,
    // загруженной MTKTextureLoader'ом по умолчанию (GL-конвенция).
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

    // --- альфа-маска: где деформировать, а где оставить как есть ---
    float maskA = 1.0;
    if (u.misc.x > 0.5) {
        maskA = maskTex.sample(smp, uv).a;
    }

    float2 disp = float2(0.0);

    // --- ЖЕЛЕ / ПРУЖИНА ---
    // Затухающая синусоида: амплитуда ~ импульс акселерометра,
    // направление ~ вектор импульса, фаза бежит и по времени, и по
    // проекции uv на направление импульса (получается дрожание-желе,
    // а не плоский сдвиг).
    if (u.paramsB.w < 0.5 || u.paramsB.w > 1.5) {
        float t   = u.impulse.w;
        float2 dir = u.impulse.xy; // уже нормализован на CPU
        float decay = exp(-u.paramsB.x * t * 2.5);
        float proj  = dot(uv - float2(0.5), dir);
        float wave  = sin(proj * 22.0 - t * u.misc.y);
        float amp   = u.impulse.z * u.paramsA.w * decay * wave;
        disp += dir * amp * 0.07;
    }

    // --- НАКЛОН (пружина, интегрируется на CPU) ---
    if (u.paramsB.w < 0.5 || u.paramsB.w > 1.5) {
        disp += float2(u.paramsB.y, u.paramsB.z) * 0.05;
    }

    // --- ВОДНАЯ РЯБЬ ---
    if (u.paramsB.w > 0.5) {
        float t = u.ripple.z;
        if (t < 3.5 && u.ripple.w > 0.001) {
            // круговой фронт в пиксельном соотношении экрана
            float aspect = u.paramsA.x / max(u.paramsA.y, 1.0);
            float2 d    = (uv - u.ripple.xy) * float2(aspect, 1.0);
            float dist  = length(d) + 1e-5;
            float2 radial = d / dist;
            float front = dist - t * 0.85;                 // скорость фронта
            // гауссов пакет вокруг фронта + затухание по времени и расстоянию
            float env = exp(-front * front / 0.0045)
                      * exp(-t * 1.8)
                      * exp(-dist * 1.1);
            disp += radial * env * sin(front * 55.0)
                  * 0.055 * u.ripple.w * u.paramsA.w;
        }
    }

    // --- гасим деформацию у краёв, чтобы текстура не тянулась за пределы ---
    float2 edge = smoothstep(float2(0.0), float2(0.07), uv)
                * smoothstep(float2(0.0), float2(0.07), 1.0 - uv);
    disp *= edge * maskA;

    // --- преломление: лёгкая хроматическая дисперсия по смещённым UV ---
    float2 uvr = uv + disp * 0.90;
    float2 uvg = uv + disp;
    float2 uvb = uv + disp * 1.10;
    float4 col;
    col.r = wallTex.sample(smp, uvr).r;
    col.g = wallTex.sample(smp, uvg).g;
    col.b = wallTex.sample(smp, uvb).b;
    col.a = 1.0;
    return col;
}
