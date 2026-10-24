//
//  DHButtonManager.m
//  iOSDebugHelper
//  透传Window：只有按钮可点，其他触摸穿透给App
//

#import "DHButtonManager.h"
#import "DHMainMenuViewController.h"
#import "DHLogManager.h"

static NSString *const kDHButtonSizeKey   = @"DHButtonSize";
static NSString *const kDHButtonAlphaKey  = @"DHButtonAlpha";
static NSString *const kDHButtonPosXKey   = @"DHButtonPosX";
static NSString *const kDHButtonPosYKey   = @"DHButtonPosY";

@class DHButtonManager;

@interface DHPassthroughWindow : UIWindow
@end
@implementation DHPassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // 只有落在悬浮按钮（外扩8pt容错）上才返回按钮，其余一律nil让事件穿透给App。
    UIButton *btn = [DHButtonManager sharedManager].floatingButton;
    if (btn && btn.superview) {
        // 按钮直接加在铺满窗口的 rootVC.view 上，frame 即窗口坐标，直接判定，避免 convertPoint 错位
        CGRect hitRect = CGRectInset(btn.frame, -8, -8);
        if (CGRectContainsPoint(hitRect, point)) return btn;
    }
    return nil;
}
@end

@implementation DHButtonManager

+ (instancetype)sharedManager {
    static DHButtonManager *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [self new]; });
    return m;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _buttonSize = 60;
        _buttonAlpha = 0.7;
        _buttonPosition = CGPointMake(20, 200);
        [self loadSettings];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onLocateScanClass:) name:@"DHOpenScanLocateClass" object:nil];
    }
    return self;
}

// 待全局扫描定位的类名（存 NSUserDefaults，主菜单打开后消费）
- (void)onLocateScanClass:(NSNotification *)note {
    [[NSUserDefaults standardUserDefaults] setObject:note.userInfo[@"className"] forKey:@"DHPendingLocateClass"];
    [[NSUserDefaults standardUserDefaults] setObject:note.userInfo[@"methodName"] ?: @"" forKey:@"DHPendingLocateMethod"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self buttonTapped]; // 打开主菜单，由主菜单消费待办并跳转定位
}

- (void)showFloatingButton {
    // 透传Window，windowLevel最高但不拦截触摸
    DHPassthroughWindow *window = [[DHPassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    // 提高windowLevel，盖过 App 的 alert / 登录弹窗专用窗口，确保悬浮球始终可点
    window.windowLevel = UIWindowLevelAlert + 1000;
    window.backgroundColor = [UIColor clearColor];
    window.hidden = NO;
    // 兼容iOS 13+ Scene，优先挂到前台活跃场景
    if (@available(iOS 13.0, *)) {
        UIWindowScene *target = nil;
        for (UIWindowScene *sc in [UIApplication sharedApplication].connectedScenes) {
            if ([sc isKindOfClass:[UIWindowScene class]] && sc.activationState == UISceneActivationStateForegroundActive) { target = sc; break; }
        }
        if (!target) target = (UIWindowScene *)[UIApplication sharedApplication].connectedScenes.allObjects.firstObject;
        if ([target isKindOfClass:[UIWindowScene class]]) window.windowScene = target;
    }
    window.rootViewController = [UIViewController new];
    window.rootViewController.view.backgroundColor = [UIColor clearColor];
    window.userInteractionEnabled = YES;
    window.clipsToBounds = NO;
    
    self.floatingWindow = window;
    
    self.floatingButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.floatingButton.frame = CGRectMake(self.buttonPosition.x, self.buttonPosition.y, self.buttonSize, self.buttonSize);
    self.floatingButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:self.buttonAlpha];
    self.floatingButton.layer.cornerRadius = self.buttonSize / 2;
    self.floatingButton.alpha = self.buttonAlpha;
    self.floatingButton.layer.zPosition = 9999;
    [self.floatingButton setTitle:@"🔧" forState:UIControlStateNormal];
    self.floatingButton.titleLabel.font = [UIFont systemFontOfSize:self.buttonSize * 0.4];
    
    // 拖拽手势
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.floatingButton addGestureRecognizer:pan];
    
    // 点击
    [self.floatingButton addTarget:self action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];
    
    [window.rootViewController.view addSubview:self.floatingButton];
    DHLogInfo(@"悬浮球已显示(透传Window)");
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIButton *btn = (UIButton *)gesture.view;
    CGPoint translation = [gesture translationInView:btn.superview];
    btn.center = CGPointMake(btn.center.x + translation.x, btn.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:btn.superview];

    if (gesture.state == UIGestureRecognizerStateEnded) {
        self.buttonPosition = btn.frame.origin;
        [self saveSettings];
    }
}

- (void)buttonTapped {
    DHLogInfo(@"打开主菜单");
    
    // 找到最上层的window和VC
    UIWindow *keyWindow = nil;
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *w in scene.windows) {
                    if (!w.hidden && w.windowLevel == UIWindowLevelNormal) {
                        keyWindow = w;
                        break;
                    }
                }
            }
            if (keyWindow) break;
        }
    }
    if (!keyWindow) keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) keyWindow = [UIApplication sharedApplication].windows.firstObject;
    
    UIViewController *topVC = keyWindow.rootViewController;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;
    
    DHMainMenuViewController *menu = [[DHMainMenuViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:menu];
    [topVC presentViewController:nav animated:YES completion:nil];
}

- (void)hideFloatingButton {
    [self.floatingButton removeFromSuperview];
    self.floatingButton = nil;
    self.floatingWindow.hidden = YES;
    self.floatingWindow = nil;
}

- (void)resetPosition {
    self.buttonPosition = CGPointMake(20, 200);
    self.floatingButton.frame = CGRectMake(20, 200, self.buttonSize, self.buttonSize);
    [self saveSettings];
}

- (void)saveSettings {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setDouble:self.buttonSize forKey:kDHButtonSizeKey];
    [ud setDouble:self.buttonAlpha forKey:kDHButtonAlphaKey];
    [ud setDouble:self.buttonPosition.x forKey:kDHButtonPosXKey];
    [ud setDouble:self.buttonPosition.y forKey:kDHButtonPosYKey];
    [ud synchronize];
}

- (void)loadSettings {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud doubleForKey:kDHButtonSizeKey] > 0) self.buttonSize = [ud doubleForKey:kDHButtonSizeKey];
    if ([ud doubleForKey:kDHButtonAlphaKey] > 0) self.buttonAlpha = [ud doubleForKey:kDHButtonAlphaKey];
    self.buttonPosition = CGPointMake([ud doubleForKey:kDHButtonPosXKey] ?: 20, [ud doubleForKey:kDHButtonPosYKey] ?: 200);
}

@end
