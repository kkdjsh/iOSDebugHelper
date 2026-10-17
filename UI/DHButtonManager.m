//
//  DHButtonManager.m
//  iOSDebugHelper
//

#import "DHButtonManager.h"
#import "DHMainMenuViewController.h"
#import "DHLogManager.h"

static NSString *const kDHButtonSizeKey   = @"DHButtonSize";
static NSString *const kDHButtonAlphaKey  = @"DHButtonAlpha";
static NSString *const kDHButtonPosXKey   = @"DHButtonPosX";
static NSString *const kDHButtonPosYKey   = @"DHButtonPosY";

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
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) return;

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

    [keyWindow addSubview:self.floatingButton];
    DHLogInfo(@"悬浮球已显示");
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
