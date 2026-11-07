// WiggleTheme — «жидкие» обои экрана блокировки в стиле OriginOS 7 (Wiggle Theme).
//
// 0.3.0:
//  - Зона эффекта (uniform в шейдер): весь экран / верх / низ / центр +
//    отступы в %; края зоны мягко размыты. PNG-маска осталась как доп. слой.
//  - Новые настройки: скорость ряби, скорость желе, сила преломления,
//    порог тряски — всё применяется на лету.
//
// Rootless/rootful, iOS 15–18, A12+, только SpringBoard.

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <CoreMotion/CoreMotion.h>
#import <QuartzCore/QuartzCore.h>
#import <simd/simd.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define WG_PREFS_ID CFSTR("com.wiggletheme.defaults")

#pragma mark - Настройки (com.wiggletheme.defaults)

static id WGValue(NSString *key, id def) {
    CFPreferencesAppSynchronize(WG_PREFS_ID);
    id v = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, WG_PREFS_ID));
    return v ? v : def;
}

static BOOL WGBool(NSString *key, BOOL def)      { return [WGValue(key, @(def)) boolValue]; }
static CGFloat WGNum(NSString *key, CGFloat def) { return [WGValue(key, @(def)) doubleValue]; }
static NSString *WGStr(NSString *key, NSString *def) { return WGValue(key, def); }

#define WGLog(fmt, ...) \
    do { if (WGBool(@"Debug", NO)) NSLog(@"[WiggleTheme] " fmt, ##__VA_ARGS__); } while (0)

static inline double WGClamp(double v, double lo, double hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

#pragma mark - Uniforms (ВНИМАНИЕ: держать синхронно с WallpaperShader.metal!)

struct WGUniforms {
    vector_float4 paramsA; // viewW, viewH, (резерв), intensity
    vector_float4 paramsB; // damping, tiltX, tiltY, mode (0 желе / 1 рябь / 2 оба)
    vector_float4 impulse; // dirX, dirY, magnitude(0..1), age
    vector_float4 ripple;  // centerX, centerY (uv), age, strength(0..1)
    vector_float4 misc;    // hasMask, omega, (резерв), (резерв)
    vector_float4 zone;    // зона эффекта в uv: x0, y0, x1, y1
    vector_float4 fx;      // rippleSpeed, jellySpeed, refraction, zoneEdge
};

#ifdef WG_ROOTLESS
static NSString *const WGShaderPath = @"/var/jb/Library/Application Support/WiggleTheme/WallpaperShader.metal";
#else
static NSString *const WGShaderPath = @"/Library/Application Support/WiggleTheme/WallpaperShader.metal";
#endif

static NSString *WGShaderSource(void) {
    NSString *src = [NSString stringWithContentsOfFile:WGShaderPath
                                              encoding:NSUTF8StringEncoding
                                                 error:NULL];
    if (!src) WGLog(@"shader source not found at %@", WGShaderPath);
    return src;
}

// маска, нарисованная кистью в настройках (общая для Settings и SpringBoard)
static NSString *WGPaintedMaskPath(void) {
    NSString *base = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString *dir = [base stringByAppendingPathComponent:@"WiggleTheme"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return [dir stringByAppendingPathComponent:@"painted-mask.png"];
}

#pragma mark - Metal-вью (слой над обоями)

@interface WGMetalView : UIView
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> queue;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipeline;
@property (nonatomic, strong) id<MTLBuffer> uniformsBuffer;
@property (nonatomic, strong) id<MTLTexture> wallTexture;
@property (nonatomic, strong) id<MTLTexture> maskTexture;
@property (nonatomic, assign, readonly) BOOL pipelineReady;
- (void)ensurePipeline;
- (void)setWallpaperImage:(UIImage *)img maskImage:(UIImage *)mask;
- (void)drawFrame:(const WGUniforms *)u;
@end

@implementation WGMetalView

+ (Class)layerClass {
    return [CAMetalLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.opaque = YES;
        self.userInteractionEnabled = NO;
        CAMetalLayer *l = (CAMetalLayer *)self.layer;
        l.device = MTLCreateSystemDefaultDevice();
        if (!l.device) {
            WGLog(@"MTLCreateSystemDefaultDevice failed");
            return self;
        }
        l.pixelFormat = MTLPixelFormatBGRA8Unorm;
        l.framebufferOnly = YES;
        l.maximumDrawableCount = 2;
        l.presentsWithTransaction = NO;
        l.opaque = YES;
        self.device = l.device;
        [self ensurePipeline];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CAMetalLayer *l = (CAMetalLayer *)self.layer;
    CGFloat scale = self.window.screen.scale ?: [UIScreen mainScreen].scale;
    l.drawableSize = CGSizeMake(self.bounds.size.width * scale,
                                self.bounds.size.height * scale);
}

- (void)ensurePipeline {
    if (self.pipelineReady || !self.device) return;

    NSString *src = WGShaderSource();
    if (!src) return;

    NSError *err = nil;
    id<MTLLibrary> lib = [self.device newLibraryWithSource:src options:nil error:&err];
    if (!lib) {
        WGLog(@"MTLLibrary compile failed: %@", err.localizedDescription);
        return;
    }

    MTLRenderPipelineDescriptor *d = [[MTLRenderPipelineDescriptor alloc] init];
    d.vertexFunction = [lib newFunctionWithName:@"wgVert"];
    d.fragmentFunction = [lib newFunctionWithName:@"wgFrag"];
    d.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

    self.pipeline = [self.device newRenderPipelineStateWithDescriptor:d error:&err];
    if (!self.pipeline) {
        WGLog(@"pipeline state failed: %@", err.localizedDescription);
        return;
    }

    self.queue = [self.device newCommandQueue];
    self.uniformsBuffer = [self.device newBufferWithLength:sizeof(WGUniforms)
                                                  options:MTLResourceStorageModeShared];
    _pipelineReady = YES;
    WGLog(@"metal pipeline ready");
}

- (void)setWallpaperImage:(UIImage *)img maskImage:(UIImage *)mask {
    if (!self.pipelineReady || !img.CGImage) return;

    NSError *err = nil;
    MTKTextureLoader *loader = [[MTKTextureLoader alloc] initWithDevice:self.device];
    NSDictionary *opts = @{ MTKTextureLoaderOptionSRGB : @NO };

    id<MTLTexture> t = [loader newTextureWithCGImage:img.CGImage options:opts error:&err];
    if (!t) {
        WGLog(@"wallpaper texture failed: %@", err.localizedDescription);
        return;
    }
    self.wallTexture = t;

    if (mask.CGImage) {
        self.maskTexture = [loader newTextureWithCGImage:mask.CGImage options:opts error:&err];
        if (!self.maskTexture) WGLog(@"mask texture failed: %@", err.localizedDescription);
    } else {
        self.maskTexture = nil;
    }
    WGLog(@"textures set: %@ x%@, mask=%d",
          @(img.size.width), @(img.size.height), self.maskTexture != nil);
}

- (void)drawFrame:(const WGUniforms *)u {
    if (!self.pipelineReady || !self.wallTexture) return;

    CAMetalLayer *l = (CAMetalLayer *)self.layer;
    id<CAMetalDrawable> drawable = [l nextDrawable];
    if (!drawable) return;

    memcpy(self.uniformsBuffer.contents, u, sizeof(WGUniforms));

    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = drawable.texture;
    rp.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLCommandBuffer> cb = [self.queue commandBuffer];
    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
    [enc setRenderPipelineState:self.pipeline];
    [enc setFragmentBuffer:self.uniformsBuffer offset:0 atIndex:0];
    [enc setFragmentTexture:self.wallTexture atIndex:0];
    if (self.maskTexture) [enc setFragmentTexture:self.maskTexture atIndex:1];
    [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [enc endEncoding];
    [cb presentDrawable:drawable];
    [cb commit];
}

@end

#pragma mark - Движок: датчики + пружина + рендер-цикл

static void *kWGContentsCtx = &kWGContentsCtx;

@interface WGEngine : NSObject
@property (nonatomic, strong) CMMotionManager *motion;
@property (nonatomic, strong) NSOperationQueue *motionQueue;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, weak) WGMetalView *metalView;
@property (nonatomic, weak) UIView *wallpaperView;
@property (nonatomic, assign) BOOL locked;
@property (nonatomic, assign) BOOL needsSnapshot;
@property (nonatomic, assign) BOOL oneFrame;

// пружина наклона
@property (nonatomic, assign) double offX, offY, velX, velY;
@property (nonatomic, assign) double tiltTargetX, tiltTargetY;

// импульс тряски / ряби
@property (nonatomic, assign) double impulseDirX, impulseDirY, impulseMag, impulseAge;
@property (nonatomic, assign) double rippleX, rippleY, rippleAge, rippleStrength;
@property (nonatomic, assign) double lastShakeAt;

// кэш настроек
@property (nonatomic, assign) BOOL pEnabled;
@property (nonatomic, assign) NSInteger pMode;
@property (nonatomic, assign) NSInteger pZoneMode;
@property (nonatomic, assign) CGFloat pIntensity, pDamping, pTilt;
@property (nonatomic, assign) CGFloat pInsetTop, pInsetBottom, pInsetLeft, pInsetRight;
@property (nonatomic, assign) CGFloat pRippleSpeed, pJellySpeed, pRefraction, pSensitivity;
@property (nonatomic, assign) BOOL pPaintedEnabled;
@property (nonatomic, assign) BOOL maskIsPainted;
@property (nonatomic, copy) NSString *pMaskPath;
@property (nonatomic, assign) NSTimeInterval prefsStamp;
@end

@implementation WGEngine

+ (instancetype)shared {
    static WGEngine *e = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ e = [[WGEngine alloc] init]; });
    return e;
}

#pragma mark Настройки

- (void)refreshPrefsIfNeeded {
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (self.prefsStamp != 0 && now - self.prefsStamp < 0.5) return;
    self.prefsStamp = now;

    self.pEnabled     = WGBool(@"Enabled", YES);
    self.pMode        = [WGValue(@"Mode", @2) integerValue];
    self.pZoneMode    = [WGValue(@"ZoneMode", @0) integerValue];
    self.pIntensity   = WGNum(@"Intensity", 0.6);
    self.pDamping     = WGNum(@"Damping", 0.18);
    self.pTilt        = WGNum(@"TiltStrength", 0.5);
    self.pInsetTop    = WGNum(@"InsetTop", 0.0);
    self.pInsetBottom = WGNum(@"InsetBottom", 0.0);
    self.pInsetLeft   = WGNum(@"InsetLeft", 0.0);
    self.pInsetRight  = WGNum(@"InsetRight", 0.0);
    self.pRippleSpeed = WGNum(@"RippleSpeed", 0.85);
    self.pJellySpeed  = WGNum(@"JellySpeed", 1.0);
    self.pRefraction  = WGNum(@"Refraction", 0.6);
    self.pSensitivity = WGNum(@"Sensitivity", 0.85);
    self.pPaintedEnabled = WGBool(@"PaintedMaskEnabled", NO);
    self.pMaskPath    = WGStr(@"MaskPath", @"");
}

// зона эффекта в uv-координатах (y=0 — низ экрана, y=1 — верх)
- (vector_float4)zoneUV {
    float x0 = 0.0f, y0 = 0.0f, x1 = 1.0f, y1 = 1.0f;
    switch (self.pZoneMode) {
        case 1: y0 = 0.5f; break; // верхняя половина
        case 2: y1 = 0.5f; break; // нижняя половина
        case 3: x0 = y0 = 0.2f; x1 = y1 = 0.8f; break; // центральная область
        default: break;
    }
    x0 += (float)MIN(MAX(self.pInsetLeft, 0), 45) / 100.0f;
    x1 -= (float)MIN(MAX(self.pInsetRight, 0), 45) / 100.0f;
    y0 += (float)MIN(MAX(self.pInsetBottom, 0), 45) / 100.0f;
    y1 -= (float)MIN(MAX(self.pInsetTop, 0), 45) / 100.0f;
    x0 = MIN(MAX(x0, 0.0f), x1 - 0.1f);
    y0 = MIN(MAX(y0, 0.0f), y1 - 0.1f);
    x1 = MAX(x1, x0 + 0.1f);
    y1 = MAX(y1, y0 + 0.1f);
    return (vector_float4){ x0, y0, x1, y1 };
}

#pragma mark Установка над обоями

- (void)installInView:(UIView *)wallpaper {
    [self refreshPrefsIfNeeded];
    if (!self.pEnabled) {
        [self disableOverlay];
        return;
    }

    if (self.metalView && self.metalView.superview == wallpaper) return;

    if (!self.metalView) {
        WGMetalView *mv = [[WGMetalView alloc] initWithFrame:wallpaper.bounds];
        if (!mv.device) return;

        self.metalView = mv;
        self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        self.link.preferredFramesPerSecond = 60;
        [self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        self.link.paused = YES;
    }

    [self removeContentsObserver];
    self.wallpaperView = wallpaper;

    [wallpaper addSubview:self.metalView];
    self.metalView.frame = wallpaper.bounds;
    self.metalView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    [self addContentsObserver];

    self.needsSnapshot = YES;
    [self applyLockState];
    WGLog(@"installed over %@", NSStringFromClass(wallpaper.class));
}

- (void)addContentsObserver {
    @try {
        [self.wallpaperView.layer addObserver:self forKeyPath:@"contents" options:0 context:kWGContentsCtx];
    } @catch (NSException *ex) {
        WGLog(@"KVO add failed: %@", ex);
    }
}

- (void)removeContentsObserver {
    @try {
        [self.wallpaperView.layer removeObserver:self forKeyPath:@"contents" context:kWGContentsCtx];
    } @catch (NSException *ex) {
        WGLog(@"KVO remove failed: %@", ex);
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                          change:(NSDictionary *)change context:(void *)context {
    if (context == kWGContentsCtx) {
        self.needsSnapshot = YES;
        self.oneFrame = YES;
        [self resumeRender];
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)disableOverlay {
    [self.motion stopDeviceMotionUpdates];
    self.link.paused = YES;
    [self.metalView removeFromSuperview];
}

#pragma mark Снапшот обоев → текстура

- (void)refreshSnapshot {
    UIView *wp = self.wallpaperView;
    WGMetalView *mv = self.metalView;
    if (!wp || wp.bounds.size.width < 10 || !mv) return;

    // прячем себя, чтобы не захватить прошлый кадр Metal (нет петли обратной связи)
    BOOL wasHidden = mv.hidden;
    mv.hidden = YES;

    UIGraphicsImageRendererFormat *fmt = [[UIGraphicsImageRendererFormat alloc] init];
    fmt.opaque = NO;
    fmt.scale = wp.window.screen.scale ?: [UIScreen mainScreen].scale;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithBounds:wp.bounds format:fmt];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        [wp drawViewHierarchyInRect:wp.bounds afterScreenUpdates:NO];
    }];

    mv.hidden = wasHidden;

    if (!img || img.size.width < 10) {
        WGLog(@"snapshot failed");
        return;
    }

    UIImage *mask = nil;
    self.maskIsPainted = NO;
    if (self.pPaintedEnabled) {
        mask = [UIImage imageWithContentsOfFile:WGPaintedMaskPath()];
        self.maskIsPainted = (mask != nil);
        if (!mask) WGLog(@"painted mask missing — falling back to zone");
    }
    if (!mask && self.pMaskPath.length > 0) {
        mask = [UIImage imageWithContentsOfFile:self.pMaskPath];
        if (!mask) WGLog(@"mask PNG not found: %@", self.pMaskPath);
    }

    [mv setWallpaperImage:img maskImage:mask];

    self.oneFrame = YES;
    [self resumeRender];
    WGLog(@"snapshot ok %@", NSStringFromCGSize(img.size));
}

#pragma mark Состояние блокировки (батарея: датчики только на локскрине)

- (void)refreshLockState {
    [self refreshPrefsIfNeeded];
    if (!self.pEnabled) {
        [self disableOverlay];
        return;
    }

    BOOL locked = NO;
    Class cls = objc_getClass("SBLockScreenManager");
    if (cls) {
        id inst = [(id)cls performSelector:@selector(sharedInstance)];
        if (inst && [(id)inst respondsToSelector:@selector(deviceIsLocked)]) {
            locked = ((BOOL (*)(id, SEL))objc_msgSend)(inst, @selector(deviceIsLocked));
        }
    }
    self.locked = locked;
    [self applyLockState];
}

- (void)applyLockState {
    BOOL want = self.pEnabled && self.locked;
    if (want) {
        [self startMotion];
        self.needsSnapshot = YES;
        self.oneFrame = YES;
        [self resumeRender];
    } else {
        [self.motion stopDeviceMotionUpdates];
        self.link.paused = YES;
        WGLog(@"lock state -> %d, motion/render paused", self.locked);
    }
}

- (void)startMotion {
    if (!self.motion) {
        self.motion = [[CMMotionManager alloc] init];
        self.motionQueue = [[NSOperationQueue alloc] init];
        self.motionQueue.name = @"com.wiggletheme.motion";
        self.motion.deviceMotionUpdateInterval = 1.0 / 60.0;
    }
    if (self.motion.isDeviceMotionActive) return;

    __weak typeof(self) w = self;
    [self.motion startDeviceMotionUpdatesToQueue:self.motionQueue
                                     withHandler:^(CMDeviceMotion *m, NSError *error) {
        __strong typeof(w) s = w;
        if (s) [s motionTick:m];
    }];
    WGLog(@"deviceMotion started");
}

#pragma mark Датчики (фоновый поток) → главный поток

- (void)motionTick:(CMDeviceMotion *)m {
    double rateX = m.rotationRate.x;
    double rateZ = m.rotationRate.z;
    double roll = m.attitude.roll;
    double pitch = m.attitude.pitch;
    CMAcceleration a = m.userAcceleration; // без гравитации, в g
    double mag = sqrt(a.x * a.x + a.y * a.y + a.z * a.z);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.pEnabled) return;

        // микрорывки от гироскопа подпитывают пружину («дрожит»)
        self.velX += rateZ * 0.006;
        self.velY += rateX * 0.006;

        self.tiltTargetX = WGClamp(roll / (M_PI / 3.0), -1.0, 1.0) * self.pTilt;
        self.tiltTargetY = WGClamp(pitch / (M_PI / 2.0), -1.0, 1.0) * self.pTilt * 0.5;

        double now = CACurrentMediaTime();
        if (mag > self.pSensitivity && now - self.lastShakeAt > 0.7) {
            self.lastShakeAt = now;

            double dx = a.x, dy = -a.y; // в экранные координаты (UIKit, y вниз)
            double len = hypot(dx, dy);
            if (len < 0.05) { dx = 1.0; dy = 0.0; len = 1.0; }

            self.impulseDirX = dx / len;
            self.impulseDirY = dy / len;
            self.impulseMag  = WGClamp(mag, 0.0, 3.0) / 3.0;
            self.impulseAge  = 0.0;

            self.rippleX = WGClamp(0.5 + self.impulseDirX * 0.22, 0.12, 0.88);
            self.rippleY = WGClamp(0.5 + self.impulseDirY * 0.22, 0.12, 0.88);
            self.rippleAge = 0.0;
            self.rippleStrength = self.impulseMag;

            WGLog(@"shake mag=%.2f dir=(%.2f,%.2f)", mag, self.impulseDirX, self.impulseDirY);
            [self resumeRender];
        } else if (fabs(rateX) + fabs(rateZ) > 1.2) {
            // заметное вращение телефона — будим рендер
            [self resumeRender];
        }
    });
}

#pragma mark Рендер-цикл

- (void)resumeRender {
    if (self.link && self.link.paused) {
        self.link.paused = NO;
        WGLog(@"render resumed");
    }
}

- (void)tick:(CADisplayLink *)dl {
    [self refreshPrefsIfNeeded];

    if (!self.pEnabled) {
        [self disableOverlay];
        return;
    }

    WGMetalView *mv = self.metalView;
    if (!mv || !mv.pipelineReady) return;
    if (!mv.window || mv.hidden) {
        self.link.paused = YES;
        return;
    }

    // снапшот делаем ДО проверки wallTexture — иначе первый кадр не наступит никогда
    if (self.needsSnapshot) {
        self.needsSnapshot = NO;
        [self refreshSnapshot];
        if (!mv.wallTexture) return;
    }

    double dt = WGClamp(dl.targetTimestamp - dl.timestamp, 0.001, 0.033);

    // пружина наклона (недодемпфированная → «желейный» возврат)
    self.velX += ((self.tiltTargetX - self.offX) * 120.0 - self.velX * 10.0) * dt;
    self.velY += ((self.tiltTargetY - self.offY) * 120.0 - self.velY * 10.0) * dt;
    self.offX += self.velX * dt;
    self.offY += self.velY * dt;

    self.impulseAge += dt;
    self.rippleAge += dt;

    CGFloat scale = mv.window.screen.scale ?: [UIScreen mainScreen].scale;
    double w = mv.bounds.size.width * scale;
    double h = mv.bounds.size.height * scale;
    int mode = (int)self.pMode;

    WGUniforms u;
    u.paramsA = (vector_float4){ (float)w, (float)h, 0.0f, (float)self.pIntensity };
    u.paramsB = (vector_float4){
        (float)self.pDamping,
        (float)(mode == 1 ? 0.0 : self.offX), // в режиме «только рябь» наклон выключен
        (float)(mode == 1 ? 0.0 : self.offY),
        (float)mode
    };
    u.impulse = (vector_float4){ (float)self.impulseDirX, (float)self.impulseDirY,
                                 (float)self.impulseMag, (float)self.impulseAge };
    u.ripple  = (vector_float4){ (float)self.rippleX, (float)self.rippleY,
                                 (float)self.rippleAge, (float)self.rippleStrength };
    u.misc    = (vector_float4){ mv.maskTexture ? 1.0f : 0.0f, 16.0f,
                                 self.maskIsPainted ? 0.0f : 1.0f, 0.0f };
    u.zone    = [self zoneUV];
    u.fx      = (vector_float4){ (float)self.pRippleSpeed, (float)self.pJellySpeed,
                                 (float)self.pRefraction, 0.08f };

    [mv drawFrame:&u];

    // уснуло → ставим рендер на паузу (батарея)
    BOOL springMoving = fabs(self.offX) + fabs(self.offY) + fabs(self.velX) + fabs(self.velY) > 0.004;
    BOOL impulseAlive = self.impulseMag > 0.02 && self.impulseAge < 4.0;
    BOOL rippleAlive  = self.rippleStrength > 0.02 && self.rippleAge < 3.5;
    BOOL wasOneFrame = self.oneFrame;
    self.oneFrame = NO;

    if (!springMoving && !impulseAlive && !rippleAlive && !wasOneFrame) {
        self.link.paused = YES;
        WGLog(@"effect settled — render paused");
    }
}

@end

#pragma mark - Хук SpringBoard

@interface SBFWallpaperView : UIView
@end

static BOOL WGIsLockScreenWallpaper(UIView *v) {
    for (UIView *p = v; p != nil; p = p.superview) {
        if ([NSStringFromClass(p.class) containsString:@"LockScreen"]) return YES;
    }
    return NO;
}

%hook SBFWallpaperView
- (void)layoutSubviews {
    %orig;
    if (WGIsLockScreenWallpaper(self)) {
        [[WGEngine shared] installInView:self];
    }
}
%end

static void WGLockStateChanged(CFNotificationCenterRef center, void *observer,
                               CFStringRef name, const void *object,
                               CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[WGEngine shared] refreshLockState];
    });
}

%ctor {
    @autoreleasepool {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL, WGLockStateChanged,
                                        CFSTR("com.apple.springboard.lockstate"),
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        NSLog(@"[WiggleTheme] loaded (v0.3.0)");
    }
}
