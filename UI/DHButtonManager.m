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

@interface DHPassthroughWindow : UIWindow
@end
@implementation DHPassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    // 只有命中按钮才返回，其他返回nil让事件穿透
    if (v == self.rootViewController.view || !v) return nil;
    return v;
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
    }
    return self;
}

- (void)showFloatingButton {
    // 透传Window，windowLevel最高但不拦截触摸
    DHPassthroughWindow *window = [[DHPassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    window.windowLevel = UIWindowLevelAlert + 100;
    window.backgroundColor = [UIColor clearColor];
    window.hidden = NO;
    window.rootViewController = [UIViewController new];
    window.rootViewController.view.backgroundColor = [UIColor clearColor];
    window.userInteractionEnabled = YES;

    self.floatingWindow = window;

    self.floatingButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.floatingButton.frame = CGRectMake(self.buttonPosition.x, self.buttonPosition.y, self.buttonSize, self.buttonSize);
    self.floatingButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:self.buttonAlpha];
    self.floatingButton.layer.cornerRadius = self.buttonSize / 2;
    self.floatingButton.alpha = self.buttonAlpha;
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
    UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
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
