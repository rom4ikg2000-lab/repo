// OriginDroplet — интерактивная «капля» на обоях рабочего стола в стиле OriginOS 7.
// Трясёшь телефон — капля скользит по наклону, прыгает и останавливается в новом месте.
// Тапаешь по пустому месту — капля пружинкой уезжает туда.
//
// Rootless-джейлбрейк (Dopamine / RootHide), iOS 15–16, только SpringBoard.

#import <UIKit/UIKit.h>
#import <CoreMotion/CoreMotion.h>

#define OD_PREFS_ID CFSTR("com.origindroplet.defaults")

#pragma mark - Настройки (com.origindroplet.defaults)

static id ODValue(NSString *key, id def) {
    CFPreferencesAppSynchronize(OD_PREFS_ID);
    id v = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, OD_PREFS_ID));
    return v ? v : def;
}

static BOOL ODBool(NSString *key, BOOL def) {
    return [ODValue(key, @(def)) boolValue];
}

static CGFloat ODNum(NSString *key, CGFloat def) {
    return [ODValue(key, @(def)) doubleValue];
}

static NSString *ODStr(NSString *key, NSString *def) {
    return ODValue(key, def);
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

    // свой PNG, если задан и существует
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
    // светлое ядро -> насыщенный край, полупрозрачная водяная капля
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

    // тонкий светлый ободок
    CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithWhite:1.0 alpha:0.55].CGColor);
    CGContextSetLineWidth(ctx, 1.2);
    CGContextStrokeEllipseInRect(ctx, CGRectMake(c.x - r, c.y - r, r * 2.0, r * 2.0));

    // блик слева сверху
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:1.0 alpha:0.7].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(c.x - r * 0.45, c.y - r * 0.58, r * 0.52, r * 0.32));

    CGGradientRelease(grad);
    CGColorSpaceRelease(cs);
}

@end

#pragma mark - Менеджер: физика, тряска, тапы

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
@property (nonatomic, assign) CMAcceleration lastAccel;
@property (nonatomic, assign) NSTimeInterval prefsStamp;

// закэшированные настройки (обновляются не чаще 2 раз в секунду)
@property (nonatomic, assign) BOOL pEnabled;
@property (nonatomic, assign) BOOL pShake;
@property (nonatomic, assign) BOOL pTap;
@property (nonatomic, assign) CGFloat pSize;
@property (nonatomic, assign) CGFloat pSensitivity;
@property (nonatomic, assign) CGFloat pBounce;
@property (nonatomic, copy) NSString *pImagePath;
@end

@implementation ODManager

+ (instancetype)shared {
    static ODManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [[ODManager alloc] init]; });
    return manager;
}

#pragma mark Настройки

- (void)refreshPrefsIfNeeded {
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (self.prefsStamp != 0 && now - self.prefsStamp < 0.5) return;
    self.prefsStamp = now;

    self.pEnabled     = ODBool(@"Enabled", YES);
    self.pShake       = ODBool(@"ShakeEnabled", YES);
    self.pTap         = ODBool(@"TapEnabled", YES);
    self.pSize        = ODNum(@"Size", 34.0);
    self.pSensitivity = ODNum(@"Sensitivity", 2.0);
    self.pBounce      = ODNum(@"Bounciness", 0.55);
    self.pImagePath   = ODStr(@"ImagePath", @"");
}

#pragma mark Установка капли в домашний экран

// ищем вьюху обоев на разной глубине (SBFWallpaperView / SBWallpaperView / ...)
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

        // последнее место или центр экрана
        NSUserDefaults *defs = NSUserDefaults.standardUserDefaults;
        CGFloat x = (CGFloat)[defs doubleForKey:@"od_x"];
        CGFloat y = (CGFloat)[defs doubleForKey:@"od_y"];
        if (x <= 0 && y <= 0) {
            x = homeScreen.bounds.size.width / 2.0;
            y = homeScreen.bounds.size.height / 2.0;
        }
        d.center = CGPointMake(x, y);

        // кладём каплю НА обои, ПОД иконки
        UIView *wallpaper = ODFindWallpaper(homeScreen);
        if (wallpaper && wallpaper.superview == homeScreen) {
            [homeScreen insertSubview:d aboveSubview:wallpaper];
        } else if (wallpaper) {
            // обои лежат глубже — добавляем каплю прямо в них
            wallpaper.userInteractionEnabled = YES; // чтобы капля была живой
            [wallpaper addSubview:d];
        } else {
            [homeScreen addSubview:d];
        }

        self.droplet = d;
        self.host = homeScreen;
        self.animator = [[UIDynamicAnimator alloc] initWithReferenceView:homeScreen];
        ODLog(@"droplet installed at %@ (wallpaper %@)", NSStringFromCGPoint(d.center), wallpaper ? NSStringFromClass(wallpaper.class) : @"nil");
    } else {
        // подтягиваем размер/картинку из настроек
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
        // систему могла пересобрать иерархию — возвращаем каплю, если её выкинуло
        if (!self.droplet.superview) {
            [homeScreen addSubview:self.droplet];
        }
    }

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

#pragma mark Тряска (CoreMotion)

- (void)updateMotion {
    BOOL want = self.pEnabled && self.pShake;
    if (want && !self.motion) {
        self.motion = [[CMMotionManager alloc] init];
        self.motionQueue = [[NSOperationQueue alloc] init];
        self.motionQueue.name = @"com.origindroplet.motion";
    }

    if (want && self.motion && !self.motion.isAccelerometerActive) {
        self.motion.accelerometerUpdateInterval = 1.0 / 30.0;
        __weak typeof(self) wself = self;
        [self.motion startAccelerometerUpdatesToQueue:self.motionQueue
                                            withHandler:^(CMAccelerometerData *data, NSError *error) {
            __strong typeof(wself) sself = wself;
            if (!sself) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                [sself handleAccel:data.acceleration];
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
    if (!self.pEnabled || !self.pShake) return;

    double mag = sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (mag > self.pSensitivity && now - self.lastShakeAt > 0.9) {
        self.lastShakeAt = now;
        [self shakeImpulse];
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
        case UIInterfaceOrientationLandscapeLeft:
            v = CGPointMake(y, -x); break;
        case UIInterfaceOrientationLandscapeRight:
            v = CGPointMake(-y, x); break;
        case UIInterfaceOrientationPortraitUpsideDown:
            v = CGPointMake(-x, y); break;
        default:
            v = CGPointMake(x, -y); break; // портрет: (0,-1,0) -> (0,1) вниз
    }
    CGFloat len = hypot(v.x, v.y);
    if (len < 0.15) return CGPointZero; // телефон лежит плашмя
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

#pragma mark Сцены физики

// один «заезд»: гравитация + толчок, потом капля тормозит и засыпает
- (void)beginEpisodeWithGravityDir:(CGPoint)dir magnitude:(CGFloat)magnitude kick:(CGFloat)kick {
    ODDropletView *d = self.droplet;
    if (!d || !self.animator) return;
    [self stopIdleWatch];
    [self.animator removeAllBehaviors];

    UIDynamicItemBehavior *ib = [[UIDynamicItemBehavior alloc] initWithItems:@[ d ]];
    ib.allowsRotation = NO;
    ib.elasticity = MIN(MAX(self.pBounce, 0.0), 1.0);
    ib.friction   = 0.3;
    ib.resistance = 1.2;
    self.itemBehavior = ib;
    [self.animator addBehavior:ib];

    UICollisionBehavior *col = [[UICollisionBehavior alloc] initWithItems:@[ d ]];
    col.translatesReferenceBoundsIntoBoundary = YES;
    [self.animator addBehavior:col];

    if (magnitude > 0) {
        UIGravityBehavior *g = [[UIGravityBehavior alloc] initWithItems:@[ d ]];
        g.angle = atan2(dir.y, dir.x);
        g.magnitude = magnitude;
        [self.animator addBehavior:g];
    }
    if (kick > 0) {
        CGFloat jx = arc4random_uniform(80) - 40;
        CGFloat jy = arc4random_uniform(80) - 40;
        [ib addLinearVelocity:CGPointMake(dir.x * kick + jx, dir.y * kick + jy) forItem:d];
    }

    [self startIdleWatch];
}

// капля пружинкой уезжает в точку тапа
- (void)moveDropletTo:(CGPoint)p {
    ODDropletView *d = self.droplet;
    UIView *ref = self.animator.referenceView;
    if (!d || !ref) return;

    CGFloat hw = d.bounds.size.width / 2.0, hh = d.bounds.size.height / 2.0;
    p.x = MIN(MAX(p.x, hw), ref.bounds.size.width - hw);
    p.y = MIN(MAX(p.y, hh), ref.bounds.size.height - hh);

    [self stopIdleWatch];
    [self.animator removeAllBehaviors];

    UIAttachmentBehavior *snap = [[UIAttachmentBehavior alloc] initWithItem:d attachedToAnchor:p];
    snap.length = 0;
    snap.damping = 0.65;
    snap.frequency = 3.4;
    [self.animator addBehavior:snap];

    __weak typeof(self) wself = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(wself) sself = wself;
        if (!sself) return;
        NSArray *behaviors = sself.animator.behaviors;
        if (behaviors.count == 1 && [behaviors.firstObject isKindOfClass:UIAttachmentBehavior.class]) {
            [sself restDroplet];
        }
    });
}

// тап-обработка из хука SBIconListView
- (void)handleTouchesEnded:(NSSet<UITouch *> *)touches inView:(UIView *)list {
    [self refreshPrefsIfNeeded];
    if (!self.pEnabled || !self.pTap || !self.droplet) return;

    UITouch *touch = touches.anyObject;
    if (!touch || touch.tapCount != 1) return;

    // только короткие тапы: свайпы страниц и лонг-прессы не двигают каплю
    NSTimeInterval dur = [[NSProcessInfo processInfo] systemUptime] - touch.timestamp;
    if (dur < 0 || dur > 0.45) return;

    CGPoint locInList = [touch locationInView:list];
    UIView *hit = [list hitTest:locInList withEvent:nil];
    for (UIView *v = hit; v != nil; v = v.superview) {
        if (v == list) break;
        if ([NSStringFromClass(v.class) hasPrefix:@"SBIcon"]) return; // тап по иконке
    }

    CGPoint p = [touch locationInView:self.host ?: list];
    ODLog(@"tap at %@ -> moving droplet", NSStringFromCGPoint(p));
    [self moveDropletTo:p];
}

#pragma mark Покой и память о позиции

- (void)startIdleWatch {
    [self stopIdleWatch];
    self.settleStreak = 0;
    __weak typeof(self) wself = self;
    self.idleTimer = [NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
        __strong typeof(wself) sself = wself;
        if (!sself) { [timer invalidate]; return; }
        CGPoint v = [sself.itemBehavior linearVelocityForItem:sself.droplet];
        if (hypot(v.x, v.y) < 8.0) {
            if (++sself.settleStreak >= 2) [sself restDroplet];
        } else {
            sself.settleStreak = 0;
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
        NSLog(@"[OriginDroplet] loaded (rootless)");
    }
}
