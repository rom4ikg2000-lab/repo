// OriginDroplet — интерактивная «капля» на обоях рабочего стола в стиле OriginOS 7.
//
// 0.3.0:
//  - Зона работы капли: весь экран / верх / низ / центр + тонкая подгонка
//    отступами (в % экрана). Капля не покидает зону, тапы вне зоны игнорируются.
//  - Действие по тапу: уехать к точке или отпрыгнуть от неё.
//  - Дрейф от наклона: капля медленно плывёт по наклону даже без тряски.
//  - Кнопки в настройках: «Каплю в центр», «Респринг».
//
// Rootless/rootful (Dopamine, RootHide, palera1n), iOS 15–16, только SpringBoard.

#import <UIKit/UIKit.h>
#import <CoreMotion/CoreMotion.h>
#import <stdlib.h>

#define OD_PREFS_ID CFSTR("com.origindroplet.defaults")

#pragma mark - Настройки (com.origindroplet.defaults)

static id ODValue(NSString *key, id def) {
    CFPreferencesAppSynchronize(OD_PREFS_ID);
    id v = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, OD_PREFS_ID));
    return v ? v : def;
}

static BOOL ODBool(NSString *key, BOOL def)      { return [ODValue(key, @(def)) boolValue]; }
static CGFloat ODNum(NSString *key, CGFloat def) { return [ODValue(key, @(def)) doubleValue]; }
static NSString *ODStr(NSString *key, NSString *def) { return ODValue(key, def); }

static void ODWrite(NSString *key, id value) {
    CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFTypeRef)value,
                          OD_PREFS_ID, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost);
    CFPreferencesAppSynchronize(OD_PREFS_ID);
}

#define ODLog(fmt, ...) \
    do { if (ODBool(@"Debug", NO)) NSLog(@"[OriginDroplet] " fmt, ##__VA_ARGS__); } while (0)

#pragma mark - Капля (рисуется самим твиком, PNG не нужен)

@interface ODDropletView : UIView
@property (nonatomic, assign) BOOL useCustomImage;
@property (nonatomic, copy) NSString *imagePath;
@end

@implementation ODDropletView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.opaque = NO;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGRect b = self.bounds;

    if (self.useCustomImage && self.imagePath.length > 0) {
        UIImage *img = [UIImage imageWithContentsOfFile:self.imagePath];
        if (img) {
            [img drawInRect:b];
            return;
        }
    }

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat r = MIN(b.size.width, b.size.height) / 2.0 - 1.0;
    CGPoint c = CGPointMake(b.size.width / 2.0, b.size.height / 2.0);

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGFloat comps[] = { 0.85, 0.95, 1.00, 0.35,
                        0.30, 0.62, 1.00, 0.45,
                        0.05, 0.35, 0.90, 0.55 };
    CGFloat locs[]  = { 0.0, 0.55, 1.0 };
    CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, locs, 3);

    CGContextAddEllipseInRect(ctx, CGRectMake(c.x - r, c.y - r, r * 2.0, r * 2.0));
    CGContextClip(ctx);
    CGContextDrawRadialGradient(ctx, grad,
                                CGPointMake(c.x - r * 0.25, c.y - r * 0.3), r * 0.05,
                                c, r, kCGGradientDrawsBeforeStartLocation);

    CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithWhite:1.0 alpha:0.55].CGColor);
    CGContextSetLineWidth(ctx, 1.2);
    CGContextStrokeEllipseInRect(ctx, CGRectMake(c.x - r, c.y - r, r * 2.0, r * 2.0));

    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:1.0 alpha:0.7].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(c.x - r * 0.45, c.y - r * 0.58, r * 0.52, r * 0.32));

    CGGradientRelease(grad);
    CGColorSpaceRelease(cs);
}

@end

#pragma mark - Менеджер: зона, физика, тряска, тапы, дрейф

@interface ODManager : NSObject
@property (nonatomic, strong) CMMotionManager *motion;
@property (nonatomic, strong) NSOperationQueue *motionQueue;
@property (nonatomic, strong) UIDynamicAnimator *animator;
@property (nonatomic, strong) ODDropletView *droplet;
@property (nonatomic, strong) UIDynamicItemBehavior *itemBehavior;
@property (nonatomic, strong) NSTimer *idleTimer;
@property (nonatomic, weak) UIView *host;
@property (nonatomic, assign) NSInteger settleStreak;
@property (nonatomic, assign) NSTimeInterval lastShakeAt;
@property (nonatomic, assign) NSTimeInterval lastDriftAt;
@property (nonatomic, assign) CMAcceleration lastAccel;
@property (nonatomic, assign) NSTimeInterval prefsStamp;
@property (nonatomic, assign) CGRect lastZone;

// закэшированные настройки
@property (nonatomic, assign) BOOL pEnabled;
@property (nonatomic, assign) BOOL pShake;
@property (nonatomic, assign) BOOL pTap;
@property (nonatomic, assign) BOOL pIdleDrift;
@property (nonatomic, assign) BOOL pCenterReq;
@property (nonatomic, assign) NSInteger pZoneMode;
@property (nonatomic, assign) NSInteger pTapAction;
@property (nonatomic, assign) CGFloat pSize;
@property (nonatomic, assign) CGFloat pSensitivity;
@property (nonatomic, assign) CGFloat pBounce;
@property (nonatomic, assign) CGFloat pInsetTop, pInsetBottom, pInsetLeft, pInsetRight;
@property (nonatomic, assign) CGFloat pDriftSpeed;
@property (nonatomic, copy) NSString *pImagePath;
@end

@implementation ODManager

+ (instancetype)shared {
    static ODManager *m = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [[ODManager alloc] init]; });
    return m;
}

#pragma mark Настройки

- (void)refreshPrefsIfNeeded {
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (self.prefsStamp != 0 && now - self.prefsStamp < 0.5) return;
    self.prefsStamp = now;

    self.pEnabled   = ODBool(@"Enabled", YES);
    self.pShake     = ODBool(@"ShakeEnabled", YES);
    self.pTap       = ODBool(@"TapEnabled", YES);
    self.pIdleDrift = ODBool(@"IdleDrift", NO);
    self.pZoneMode  = [ODValue(@"ZoneMode", @0) integerValue];
    self.pTapAction = [ODValue(@"TapAction", @0) integerValue];
    self.pSize      = ODNum(@"Size", 34.0);
    self.pSensitivity = ODNum(@"Sensitivity", 2.0);
    self.pBounce    = ODNum(@"Bounciness", 0.55);
    self.pInsetTop    = ODNum(@"InsetTop", 0.0);
    self.pInsetBottom = ODNum(@"InsetBottom", 0.0);
    self.pInsetLeft   = ODNum(@"InsetLeft", 0.0);
    self.pInsetRight  = ODNum(@"InsetRight", 0.0);
    self.pDriftSpeed  = ODNum(@"DriftSpeed", 0.5);
    self.pImagePath   = ODStr(@"ImagePath", @"");

    // кнопка «Каплю в центр» из настроек
    if (ODBool(@"CenterRequested", NO)) {
        ODWrite(@"CenterRequested", @NO);
        [self centerDroplet];
    }
}

#pragma mark Зона работы капли

- (CGRect)zoneRectForBounds:(CGRect)b {
    CGFloat t = 0, bo = 0, l = 0, r = 0;
    switch (self.pZoneMode) {
        case 1: bo = b.size.height * 0.5; break;                      // верхняя половина
        case 2: t  = b.size.height * 0.5; break;                      // нижняя половина
        case 3: l = r = b.size.width * 0.2;                           // центральная область
                t = bo = b.size.height * 0.2; break;
        default: break;                                               // весь экран
    }
    t  += b.size.height * MIN(MAX(self.pInsetTop, 0), 45) / 100.0;
    bo += b.size.height * MIN(MAX(self.pInsetBottom, 0), 45) / 100.0;
    l  += b.size.width  * MIN(MAX(self.pInsetLeft, 0), 45) / 100.0;
    r  += b.size.width  * MIN(MAX(self.pInsetRight, 0), 45) / 100.0;

    CGRect z = CGRectMake(l, t, b.size.width - l - r, b.size.height - t - bo);
    // страховка от слишком маленькой зоны
    if (z.size.width < 80.0)  { z.origin.x = (b.size.width - 80.0) / 2.0;  z.size.width = 80.0; }
    if (z.size.height < 80.0) { z.origin.y = (b.size.height - 80.0) / 2.0; z.size.height = 80.0; }
    return z;
}

- (void)applyZoneIfChanged {
    UIView *ref = self.droplet.superview;
    if (!ref || !self.droplet) return;
    CGRect z = [self zoneRectForBounds:ref.bounds];
    if (CGRectEqualToRect(z, self.lastZone)) return;
    self.lastZone = z;

    // капля не может жить вне зоны — подтягиваем
    CGFloat hw = self.droplet.bounds.size.width / 2.0, hh = self.droplet.bounds.size.height / 2.0;
    CGPoint c = self.droplet.center;
    c.x = MIN(MAX(c.x, z.origin.x + hw), z.origin.x + z.size.width - hw);
    c.y = MIN(MAX(c.y, z.origin.y + hh), z.origin.y + z.size.height - hh);
    if (!CGPointEqualToPoint(c, self.droplet.center)) {
        self.droplet.center = c;
        [self savePosition];
    }
    ODLog(@"zone -> %@", NSStringFromCGRect(z));
}

- (void)centerDroplet {
    UIView *ref = self.droplet.superview;
    if (!ref) return;
    CGRect z = CGRectIsEmpty(self.lastZone) ? [self zoneRectForBounds:ref.bounds] : self.lastZone;
    [self stopIdleWatch];
    [self.animator removeAllBehaviors];
    self.droplet.center = CGPointMake(z.origin.x + z.size.width / 2.0, z.origin.y + z.size.height / 2.0);
    [self savePosition];
    ODLog(@"centered");
}

#pragma mark Установка капли в домашний экран

static UIView *ODFindWallpaper(UIView *root) {
    for (UIView *v in root.subviews) {
        if ([NSStringFromClass(v.class) containsString:@"Wallpaper"]) return v;
        UIView *deep = ODFindWallpaper(v);
        if (deep) return deep;
    }
    return nil;
}

- (void)installInView:(UIView *)homeScreen {
    [self refreshPrefsIfNeeded];

    if (!self.pEnabled) {
        [self teardown];
        return;
    }

    if (!self.droplet) {
        ODDropletView *d = [[ODDropletView alloc] initWithFrame:CGRectMake(0, 0, self.pSize, self.pSize)];
        d.useCustomImage = self.pImagePath.length > 0;
        d.imagePath = self.pImagePath;

        NSUserDefaults *defs = NSUserDefaults.standardUserDefaults;
        CGFloat x = (CGFloat)[defs doubleForKey:@"od_x"];
        CGFloat y = (CGFloat)[defs doubleForKey:@"od_y"];
        if (x <= 0 && y <= 0) {
            x = homeScreen.bounds.size.width / 2.0;
            y = homeScreen.bounds.size.height / 2.0;
        }
        d.center = CGPointMake(x, y);

        UIView *wallpaper = ODFindWallpaper(homeScreen);
        if (wallpaper && wallpaper.superview == homeScreen) {
            [homeScreen insertSubview:d aboveSubview:wallpaper];
        } else if (wallpaper) {
            wallpaper.userInteractionEnabled = YES;
            [wallpaper addSubview:d];
        } else {
            [homeScreen addSubview:d];
        }

        self.droplet = d;
        self.host = homeScreen;
        self.animator = [[UIDynamicAnimator alloc] initWithReferenceView:homeScreen];
        ODLog(@"droplet installed at %@", NSStringFromCGPoint(d.center));
    } else {
        CGFloat s = self.pSize;
        if (fabs(self.droplet.bounds.size.width - s) > 0.5) {
            CGRect f = self.droplet.frame;
            f.size = CGSizeMake(s, s);
            self.droplet.frame = f;
            [self.droplet setNeedsDisplay];
        }
        BOOL custom = self.pImagePath.length > 0;
        if (custom != self.droplet.useCustomImage || ![self.droplet.imagePath isEqualToString:self.pImagePath]) {
            self.droplet.useCustomImage = custom;
            self.droplet.imagePath = self.pImagePath;
            [self.droplet setNeedsDisplay];
        }
        if (!self.droplet.superview) {
            [homeScreen addSubview:self.droplet];
        }
    }

    [self applyZoneIfChanged];
    [self updateMotion];
}

- (void)teardown {
    [self stopIdleWatch];
    [self.motion stopAccelerometerUpdates];
    [self.animator removeAllBehaviors];
    [self.droplet removeFromSuperview];
    self.droplet = nil;
    self.animator = nil;
    self.itemBehavior = nil;
}

#pragma mark Тряска и дрейф (CoreMotion)

- (void)updateMotion {
    BOOL want = self.pEnabled && (self.pShake || self.pIdleDrift);
    if (want && !self.motion) {
        self.motion = [[CMMotionManager alloc] init];
        self.motionQueue = [[NSOperationQueue alloc] init];
        self.motionQueue.name = @"com.origindroplet.motion";
    }

    if (want && self.motion && !self.motion.isAccelerometerActive) {
        self.motion.accelerometerUpdateInterval = 1.0 / 30.0;
        __weak typeof(self) w = self;
        [self.motion startAccelerometerUpdatesToQueue:self.motionQueue
                                          withHandler:^(CMAccelerometerData *data, NSError *error) {
            __strong typeof(w) s = w;
            if (!s) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                [s handleAccel:data.acceleration];
            });
        }];
        ODLog(@"accelerometer started");
    } else if (!want && self.motion && self.motion.isAccelerometerActive) {
        [self.motion stopAccelerometerUpdates];
        ODLog(@"accelerometer stopped");
    }
}

- (void)handleAccel:(CMAcceleration)a {
    self.lastAccel = a;
    if (!self.pEnabled) return;

    double mag = sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;

    // тряска
    if (self.pShake && mag > self.pSensitivity && now - self.lastShakeAt > 0.9) {
        self.lastShakeAt = now;
        [self shakeImpulse];
        return;
    }

    // дрейф от наклона: наклонили и держим — капля медленно плывёт «вниз»
    if (self.pIdleDrift && self.animator.behaviors.count == 0
        && now - self.lastShakeAt > 1.2 && now - self.lastDriftAt > 2.0) {
        CGPoint dir = [self screenDownVector];
        double tilt = hypot(a.x, a.y);
        if (!CGPointEqualToPoint(dir, CGPointZero) && tilt > 0.3) {
            self.lastDriftAt = now;
            CGFloat speed = MIN(MAX(self.pDriftSpeed, 0.0), 1.0);
            [self beginEpisodeWithGravityDir:dir
                                   magnitude:(CGFloat)(0.2 + 0.5 * speed)
                                        kick:(CGFloat)(20 + 60 * speed)];
            ODLog(@"drift dir=(%.2f,%.2f) speed=%.2f", dir.x, dir.y, speed);
        }
    }
}

// куда «падать» на экране с учётом ориентации устройства
- (CGPoint)screenDownVector {
    UIInterfaceOrientation o = UIInterfaceOrientationPortrait;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            o = ((UIWindowScene *)scene).interfaceOrientation;
            break;
        }
    }
    double x = self.lastAccel.x, y = self.lastAccel.y;
    CGPoint v;
    switch (o) {
        case UIInterfaceOrientationLandscapeLeft:  v = CGPointMake(y, -x); break;
        case UIInterfaceOrientationLandscapeRight: v = CGPointMake(-y, x); break;
        case UIInterfaceOrientationPortraitUpsideDown: v = CGPointMake(-x, y); break;
        default: v = CGPointMake(x, -y); break;
    }
    CGFloat len = hypot(v.x, v.y);
    if (len < 0.15) return CGPointZero;
    return CGPointMake(v.x / len, v.y / len);
}

- (void)shakeImpulse {
    CGPoint dir = [self screenDownVector];
    if (CGPointEqualToPoint(dir, CGPointZero)) {
        CGFloat ang = arc4random_uniform(360) / 180.0 * M_PI;
        dir = CGPointMake(cos(ang), sin(ang));
    }
    CGFloat magnitude = 1.6 + (arc4random_uniform(15) / 10.0);
    CGFloat kick = 160 + arc4random_uniform(160);
    ODLog(@"shake! dir=(%.2f, %.2f) mag=%.2f kick=%.0f", dir.x, dir.y, magnitude, kick);
    [self beginEpisodeWithGravityDir:dir magnitude:magnitude kick:kick];
}

#pragma mark Сцены физики (границы = зона капли)

- (void)beginEpisodeWithGravityDir:(CGPoint)dir magnitude:(CGFloat)magnitude kick:(CGFloat)kick {
    ODDropletView *d = self.droplet;
    UIView *ref = self.animator.referenceView;
    if (!d || !self.animator || !ref) return;
    [self applyZoneIfChanged];
    [self stopIdleWatch];
    [self.animator removeAllBehaviors];

    UIDynamicItemBehavior *ib = [[UIDynamicItemBehavior alloc] initWithItems:@[ d ]];
    ib.allowsRotation = NO;
    ib.elasticity = MIN(MAX(self.pBounce, 0.0), 1.0);
    ib.friction   = 0.3;
    ib.resistance = 1.2;
    self.itemBehavior = ib;
    [self.animator addBehavior:ib];

    // границы зоны вместо всего экрана
    UICollisionBehavior *col = [[UICollisionBehavior alloc] initWithItems:@[ d ]];
    CGRect z = CGRectIsEmpty(self.lastZone) ? [self zoneRectForBounds:ref.bounds] : self.lastZone;
    self.lastZone = z;
    UIBezierPath *top    = [UIBezierPath bezierPath];
    [top moveToPoint:CGPointMake(z.origin.x, z.origin.y)];
    [top addLineToPoint:CGPointMake(z.origin.x + z.size.width, z.origin.y)];
    UIBezierPath *bottom = [UIBezierPath bezierPath];
    [bottom moveToPoint:CGPointMake(z.origin.x, z.origin.y + z.size.height)];
    [bottom addLineToPoint:CGPointMake(z.origin.x + z.size.width, z.origin.y + z.size.height)];
    UIBezierPath *left   = [UIBezierPath bezierPath];
    [left moveToPoint:CGPointMake(z.origin.x, z.origin.y)];
    [left addLineToPoint:CGPointMake(z.origin.x, z.origin.y + z.size.height)];
    UIBezierPath *right  = [UIBezierPath bezierPath];
    [right moveToPoint:CGPointMake(z.origin.x + z.size.width, z.origin.y)];
    [right addLineToPoint:CGPointMake(z.origin.x + z.size.width, z.origin.y + z.size.height)];
    [col addBoundaryWithIdentifier:@"top"    forPath:top];
    [col addBoundaryWithIdentifier:@"bottom" forPath:bottom];
    [col addBoundaryWithIdentifier:@"left"   forPath:left];
    [col addBoundaryWithIdentifier:@"right"  forPath:right];
    [self.animator addBehavior:col];

    if (magnitude > 0) {
        UIGravityBehavior *g = [[UIGravityBehavior alloc] initWithItems:@[ d ]];
        g.angle = atan2(dir.y, dir.x);
        g.magnitude = magnitude;
        [self.animator addBehavior:g];
    }
    if (kick > 0) {
        CGFloat jx = arc4random_uniform(60) - 30;
        CGFloat jy = arc4random_uniform(60) - 30;
        [ib addLinearVelocity:CGPointMake(dir.x * kick + jx, dir.y * kick + jy) forItem:d];
    }

    [self startIdleWatch];
}

// капля пружинкой уезжает в точку тапа (только если тап внутри зоны)
- (void)moveDropletTo:(CGPoint)p {
    ODDropletView *d = self.droplet;
    UIView *ref = self.animator.referenceView;
    if (!d || !ref) return;

    CGRect z = CGRectIsEmpty(self.lastZone) ? [self zoneRectForBounds:ref.bounds] : self.lastZone;
    if (!CGRectContainsPoint(z, p)) {
        ODLog(@"tap outside zone ignored");
        return;
    }

    CGFloat hw = d.bounds.size.width / 2.0, hh = d.bounds.size.height / 2.0;
    p.x = MIN(MAX(p.x, z.origin.x + hw), z.origin.x + z.size.width - hw);
    p.y = MIN(MAX(p.y, z.origin.y + hh), z.origin.y + z.size.height - hh);

    [self stopIdleWatch];
    [self.animator removeAllBehaviors];

    UIAttachmentBehavior *snap = [[UIAttachmentBehavior alloc] initWithItem:d attachedToAnchor:p];
    snap.length = 0;
    snap.damping = 0.65;
    snap.frequency = 3.4;
    [self.animator addBehavior:snap];

    __weak typeof(self) w = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(w) s = w;
        if (!s) return;
        NSArray *behaviors = s.animator.behaviors;
        if (behaviors.count == 1 && [behaviors.firstObject isKindOfClass:UIAttachmentBehavior.class]) {
            [s restDroplet];
        }
    });
}

// отпрыгнуть от точки тапа
- (void)bounceAwayFrom:(CGPoint)p {
    ODDropletView *d = self.droplet;
    UIView *ref = self.animator.referenceView;
    if (!d || !ref) return;
    CGPoint away = CGPointMake(d.center.x - p.x, d.center.y - p.y);
    CGFloat len = hypot(away.x, away.y);
    if (len < 1.0) { // тап точно по капле — прыжок вверх
        away = CGPointMake(0, -1);
        len = 1.0;
    }
    CGPoint dir = CGPointMake(away.x / len, away.y / len);
    ODLog(@"bounce from tap dir=(%.2f,%.2f)", dir.x, dir.y);
    [self beginEpisodeWithGravityDir:dir magnitude:1.1 kick:300];
}

// тап-обработка из хука SBIconListView
- (void)handleTouchesEnded:(NSSet<UITouch *> *)touches inView:(UIView *)list {
    [self refreshPrefsIfNeeded];
    if (!self.pEnabled || !self.pTap || !self.droplet) return;

    UITouch *touch = touches.anyObject;
    if (!touch || touch.tapCount != 1) return;

    NSTimeInterval dur = [[NSProcessInfo processInfo] systemUptime] - touch.timestamp;
    if (dur < 0 || dur > 0.45) return;

    CGPoint locInList = [touch locationInView:list];
    UIView *hit = [list hitTest:locInList withEvent:nil];
    for (UIView *v = hit; v != nil; v = v.superview) {
        if (v == list) break;
        if ([NSStringFromClass(v.class) hasPrefix:@"SBIcon"]) return;
    }

    CGPoint p = [touch locationInView:self.host ?: list];
    if (self.pTapAction == 1) {
        [self bounceAwayFrom:p];
    } else {
        [self moveDropletTo:p];
    }
}

#pragma mark Покой и память о позиции

- (void)startIdleWatch {
    [self stopIdleWatch];
    self.settleStreak = 0;
    __weak typeof(self) w = self;
    self.idleTimer = [NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
        __strong typeof(w) s = w;
        if (!s) { [timer invalidate]; return; }
        CGPoint v = [s.itemBehavior linearVelocityForItem:s.droplet];
        if (hypot(v.x, v.y) < 8.0) {
            if (++s.settleStreak >= 2) [s restDroplet];
        } else {
            s.settleStreak = 0;
        }
    }];
    [NSRunLoop.mainRunLoop addTimer:self.idleTimer forMode:NSRunLoopCommonModes];
}

- (void)stopIdleWatch {
    [self.idleTimer invalidate];
    self.idleTimer = nil;
}

- (void)restDroplet {
    [self stopIdleWatch];
    [self.animator removeAllBehaviors];
    self.itemBehavior = nil;

    if (self.droplet) {
        NSUserDefaults *defs = NSUserDefaults.standardUserDefaults;
        [defs setDouble:self.droplet.center.x forKey:@"od_x"];
        [defs setDouble:self.droplet.center.y forKey:@"od_y"];
        [defs synchronize];
    }
    ODLog(@"droplet rested at %@", self.droplet ? NSStringFromCGPoint(self.droplet.center) : @"nil");
}

- (void)savePosition {
    if (!self.droplet) return;
    NSUserDefaults *defs = NSUserDefaults.standardUserDefaults;
    [defs setDouble:self.droplet.center.x forKey:@"od_x"];
    [defs setDouble:self.droplet.center.y forKey:@"od_y"];
    [defs synchronize];
}

@end

#pragma mark - Хуки SpringBoard

@interface SBHomeScreenView : UIView
@end

@interface SBIconListView : UIView
@end

%hook SBHomeScreenView
- (void)layoutSubviews {
    %orig;
    [[ODManager shared] installInView:self];
}
%end

%hook SBIconListView
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    %orig;
    [[ODManager shared] handleTouchesEnded:touches inView:self];
}
%end

%ctor {
    @autoreleasepool {
        NSLog(@"[OriginDroplet] loaded (v0.3.0)");
    }
}
