// MaskEditorController.m — редактор зоны эффекта: рисуешь кистью по канвасу
// в форме экрана, сохраняешь — маска уезжает в твик. Кисть / ластик / размер.

#import <UIKit/UIKit.h>

static NSInteger const kWGPaintW = 512;
static NSInteger const kWGPaintH = 1109; // ~ аспект экрана блокировки

static NSString *WGEditorMaskPath(void) {
    NSString *base = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString *dir = [base stringByAppendingPathComponent:@"WiggleTheme"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return [dir stringByAppendingPathComponent:@"painted-mask.png"];
}

#pragma mark - Canvas

@interface WGMaskCanvasView : UIView
@property (nonatomic, assign) CGFloat brush; // диаметр в точках view
@property (nonatomic, assign) BOOL erasing;
- (void)strokeFrom:(CGPoint)a to:(CGPoint)b;
- (void)clearAll;
- (UIImage *)exportMask;
- (void)loadMask:(UIImage *)img;
@end

@implementation WGMaskCanvasView {
    CGContextRef _ctx;
    CGColorSpaceRef _cs;
    UIImage *_paint;
    CGPoint _last;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1.0];
        self.opaque = YES;
        self.brush = 36.0;
        _cs = CGColorSpaceCreateDeviceRGB();
    }
    return self;
}

- (void)dealloc {
    if (_ctx) CFRelease(_ctx);
    if (_cs) CFRelease(_cs);
}

- (void)ensureContext {
    if (!_ctx) {
        _ctx = CGBitmapContextCreate(NULL, kWGPaintW, kWGPaintH, 8, 0, _cs, kCGImageAlphaPremultipliedLast);
    }
}

// координаты view (y вниз) -> координаты канвы (CG, y вверх)
- (void)strokeFrom:(CGPoint)a to:(CGPoint)b {
    [self ensureContext];
    CGFloat sx = kWGPaintW / self.bounds.size.width;
    CGFloat sy = kWGPaintH / self.bounds.size.height;
    CGPoint pa = CGPointMake(a.x * sx, kWGPaintH - a.y * sy);
    CGPoint pb = CGPointMake(b.x * sx, kWGPaintH - b.y * sy);
    CGFloat r = MAX(self.brush, 4.0) * sx;

    CGFloat dist = hypot(pb.x - pa.x, pb.y - pa.y);
    NSInteger steps = (NSInteger)ceil(dist / MAX(r * 0.3, 1.0));
    for (NSInteger i = 0; i <= steps; i++) {
        CGFloat t = steps > 0 ? (CGFloat)i / steps : 0.0;
        CGPoint p = CGPointMake(pa.x + (pb.x - pa.x) * t, pa.y + (pb.y - pa.y) * t);
        CGFloat comps[] = { 1.0, 1.0, 1.0, 0.9,  1.0, 1.0, 1.0, 0.0 };
        CGFloat locs[]  = { 0.0, 1.0 };
        CGGradientRef g = CGGradientCreateWithColorComponents(_cs, comps, locs, 2);
        CGContextSetBlendMode(_ctx, self.erasing ? kCGBlendModeClear : kCGBlendModeNormal);
        CGContextDrawRadialGradient(_ctx, g, p, 0, p, r, 0);
        CFRelease(g);
    }

    CGImageRef img = CGBitmapContextCreateImage(_ctx);
    _paint = [UIImage imageWithCGImage:img];
    CFRelease(img);
    [self setNeedsDisplay];
}

- (void)clearAll {
    [self ensureContext];
    CGContextClearRect(_ctx, CGRectMake(0, 0, kWGPaintW, kWGPaintH));
    _paint = nil;
    [self setNeedsDisplay];
}

- (UIImage *)exportMask {
    [self ensureContext];
    CGImageRef img = CGBitmapContextCreateImage(_ctx);
    UIImage *u = [UIImage imageWithCGImage:img];
    CFRelease(img);
    return u;
}

- (void)loadMask:(UIImage *)img {
    [self ensureContext];
    CGContextClearRect(_ctx, CGRectMake(0, 0, kWGPaintW, kWGPaintH));
    UIGraphicsPushContext(_ctx);
    [img drawInRect:CGRectMake(0, 0, kWGPaintW, kWGPaintH)];
    UIGraphicsPopContext();
    CGImageRef out = CGBitmapContextCreateImage(_ctx);
    _paint = [UIImage imageWithCGImage:out];
    CFRelease(out);
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    [[UIColor colorWithWhite:0.06 alpha:1.0] setFill];
    CGContextFillRect(c, self.bounds);
    [_paint drawInRect:self.bounds];
    // рамка-подсказка
    [[UIColor colorWithWhite:1.0 alpha:0.12] setStroke];
    CGContextSetLineWidth(c, 1.0);
    CGContextStrokeRect(c, CGRectInset(self.bounds, 0.5, 0.5));
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *t = touches.anyObject;
    if (!t) return;
    _last = [t locationInView:self];
    [self strokeFrom:_last to:_last];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *t = touches.anyObject;
    if (!t) return;
    CGPoint p = [t locationInView:self];
    [self strokeFrom:_last to:p];
    _last = p;
}

@end

#pragma mark - Контроллер редактора

@interface WGMaskEditorController : UIViewController
@property (nonatomic, strong) WGMaskCanvasView *canvas;
@property (nonatomic, strong) UISegmentedControl *mode;
@property (nonatomic, strong) UISlider *sizeSlider;
@end

@implementation WGMaskEditorController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.title = @"Зона кистью";

    UIImage *existing = [UIImage imageWithContentsOfFile:WGEditorMaskPath()];
    if (existing) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self.canvas loadMask:existing]; });
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat vw = self.view.bounds.size.width;
    CGFloat vh = self.view.bounds.size.height;
    CGFloat bottom = self.view.safeAreaInsets.bottom;
    CGFloat controlsH = 150.0 + bottom;
    CGFloat availH = vh - controlsH - 16.0;
    CGFloat cw = MIN(vw - 24.0, availH * 0.4617);
    CGFloat ch = cw / 0.4617;
    self.canvas.frame = CGRectMake((vw - cw) / 2.0, 12.0, cw, ch);

    CGFloat y = self.canvas.frame.origin.y + ch + 14.0;
    self.mode.frame = CGRectMake(16.0, y, vw - 32.0, 32.0);
    y += 42.0;
    self.sizeSlider.frame = CGRectMake(16.0, y, vw - 32.0, 30.0);
    y += 44.0;
    // кнопки внизу
    CGFloat bw = (vw - 48.0) / 2.0;
    UIButton *clear = [self buttonWithTag:1];
    UIButton *save = [self buttonWithTag:2];
    clear.frame = CGRectMake(16.0, y, bw, 40.0);
    save.frame = CGRectMake(32.0 + bw, y, bw, 40.0);
}

- (UIButton *)buttonWithTag:(NSInteger)tag {
    UIButton *b = [self.view viewWithTag:tag];
    if (b) return b;

    b = [UIButton buttonWithType:UIButtonTypeSystem];
    if (tag == 1) {
        [b setTitle:@"Очистить" forState:UIControlStateNormal];
        [b addTarget:self action:@selector(clearTapped) forControlEvents:UIControlEventTouchUpInside];
    } else {
        [b setTitle:@"Сохранить маску" forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:17.0];
        [b addTarget:self action:@selector(saveTapped) forControlEvents:UIControlEventTouchUpInside];
    }
    b.layer.cornerRadius = 10.0;
    b.layer.borderWidth = 1.0;
    b.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
    b.tag = tag;
    [self.view addSubview:b];
    return b;
}

- (void)loadView {
    [super loadView];
    self.view.backgroundColor = [UIColor blackColor];

    self.canvas = [[WGMaskCanvasView alloc] initWithFrame:CGRectZero];
    self.canvas.layer.cornerRadius = 16.0;
    self.canvas.clipsToBounds = YES;
    [self.view addSubview:self.canvas];

    self.mode = [[UISegmentedControl alloc] initWithItems:@[ @"Кисть", @"Ластик" ]];
    self.mode.selectedSegmentIndex = 0;
    [self.mode addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.mode];

    self.sizeSlider = [[UISlider alloc] init];
    self.sizeSlider.minimumValue = 10.0;
    self.sizeSlider.maximumValue = 120.0;
    self.sizeSlider.value = 36.0;
    [self.sizeSlider addTarget:self action:@selector(sizeChanged) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.sizeSlider];

    UILabel *hint = [[UILabel alloc] init];
    hint.text = @"Рисуй, где обои должны «жидеть». Белое = эффект.";
    hint.textColor = [UIColor colorWithWhite:1.0 alpha:0.45];
    hint.font = [UIFont systemFontOfSize:12.0];
    hint.textAlignment = NSTextAlignmentCenter;
    hint.frame = CGRectMake(16.0, self.view.bounds.size.height - 64.0, self.view.bounds.size.width - 32.0, 16.0);
    hint.tag = 99;
    hint.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:hint];
}

- (void)modeChanged {
    self.canvas.erasing = (self.mode.selectedSegmentIndex == 1);
}

- (void)sizeChanged {
    self.canvas.brush = self.sizeSlider.value;
}

- (void)clearTapped {
    [self.canvas clearAll];
}

- (void)saveTapped {
    UIImage *mask = [self.canvas exportMask];
    NSData *png = UIImagePNGRepresentation(mask);
    if (![png writeToFile:WGEditorMaskPath() atomically:YES]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Не удалось сохранить маску" message:@"Попробуй ещё раз." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"ОК" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    // включаем использование нарисованной маски — твик подхватит файл
    CFPreferencesSetValue(CFSTR("PaintedMaskEnabled"), kCFBooleanTrue,
                          CFSTR("com.wiggletheme.defaults"),
                          kCFPreferencesCurrentUser, kCFPreferencesCurrentHost);
    CFPreferencesAppSynchronize(CFSTR("com.wiggletheme.defaults"));
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.wiggletheme.preferenceschanged"), NULL, NULL, true);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self.navigationController popViewControllerAnimated:YES];
    });
}

@end
