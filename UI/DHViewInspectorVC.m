#import "DHViewInspectorVC.h"

// 列表行：保存视图的非保留指针 + 层级深度
@interface DHViewRow : NSObject
@property (nonatomic, weak) UIView *view;
@property (nonatomic, assign) NSInteger depth;
@end
@implementation DHViewRow
@end

// 点选识别蒙版：透明覆盖，手指点哪命中哪个视图，自带详情/隐藏/恢复
@interface DHPickMaskVC : UIViewController
@property (nonatomic, weak) UIWindow *bottomWindow;
@end
@implementation DHPickMaskVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.12];
    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    [done setTitle:@"退出点选" forState:UIControlStateNormal];
    done.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    [done setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    done.backgroundColor = [UIColor systemRedColor];
    done.layer.cornerRadius = 22;
    CGFloat w = 140;
    done.frame = CGRectMake(([UIScreen mainScreen].bounds.size.width - w) / 2, 60, w, 44);
    [done addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:done];
}
- (void)close {
    self.view.window.hidden = YES;
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *t = touches.anyObject;
    CGPoint p = [t locationInView:self.view];
    UIView *hit = [self.bottomWindow hitTest:p withEvent:nil];
    if (!hit) return;
    [self showDetailForView:hit];
}

- (void)showDetailForView:(UIView *)v {
    NSMutableString *info = [NSMutableString string];
    [info appendFormat:@"类名：%@\n", NSStringFromClass([v class])];
    [info appendFormat:@"frame：%@\n", NSStringFromCGRect(v.frame)];
    [info appendFormat:@"hidden：%@  alpha：%.2f\n", v.hidden ? @"YES" : @"NO", v.alpha];
    NSMutableArray *chain = [NSMutableArray new];
    UIView *p = v.superview;
    while (p) { [chain addObject:NSStringFromClass([p class])]; p = p.superview; }
    [info appendFormat:@"父链：%@", [chain componentsJoinedByString:@" → "]];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"视图详情" message:info preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"隐藏该视图" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        v.hidden = YES;
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"恢复该视图" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        v.hidden = NO;
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}
@end

@interface DHViewInspectorVC ()
@property (nonatomic, copy) NSString *filterClass; // 二级：只看这个类
@property (nonatomic, strong) UIWindow *pickWindow;
@end

@implementation DHViewInspectorVC {
    NSMutableArray<DHViewRow *> *_allRows;
    NSDictionary *_groups;
    NSArray *_groupNames;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.filterClass ?: @"视图检视";

    // 二级页不显示分段控件
    if (!self.filterClass) {
        UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"按类浏览", @"点选识别"]];
        seg.selectedSegmentIndex = 0;
        [seg addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
        self.navigationItem.titleView = seg;
    }
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reloadTree)];
}

- (void)segmentChanged:(UISegmentedControl *)seg {
    if (seg.selectedSegmentIndex == 1) {
        [self startPick];
        seg.selectedSegmentIndex = 0; // 选完回到浏览态
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadTree];
}

#pragma mark - keyWindow 获取

+ (UIWindow *)dhKeyWindow {
    UIWindow *keyWindow = nil;
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *w in scene.windows) {
                    if (!w.hidden && w.windowLevel == UIWindowLevelNormal) { keyWindow = w; break; }
                }
            }
            if (keyWindow) break;
        }
    }
    if (!keyWindow) keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) keyWindow = [UIApplication sharedApplication].windows.firstObject;
    return keyWindow;
}

#pragma mark - 遍历视图树 + 按类聚合

- (void)reloadTree {
    _allRows = [NSMutableArray new];
    UIWindow *win = [DHViewInspectorVC dhKeyWindow];
    if (win) [self collectView:win depth:0];

    if (self.filterClass) {
        // 二级：只保留该类
        NSMutableArray *filtered = [NSMutableArray new];
        for (DHViewRow *r in _allRows) {
            if ([NSStringFromClass([r.view class]) isEqualToString:self.filterClass]) [filtered addObject:r];
        }
        _allRows = filtered;
        _groups = nil;
        _groupNames = nil;
    } else {
        // 一级：按类名聚合
        NSMutableDictionary *g = [NSMutableDictionary dictionary];
        for (DHViewRow *r in _allRows) {
            if (!r.view) continue;
            NSString *cls = NSStringFromClass([r.view class]);
            NSMutableArray *arr = g[cls] ?: [NSMutableArray new];
            [arr addObject:r];
            g[cls] = arr;
        }
        _groups = g;
        _groupNames = [[g allKeys] sortedArrayUsingSelector:@selector(compare:)];
    }
    [self.tableView reloadData];
}

- (void)collectView:(UIView *)v depth:(NSInteger)depth {
    if (!v) return;
    DHViewRow *row = [DHViewRow new];
    row.view = v;
    row.depth = depth;
    [_allRows addObject:row];
    for (UIView *sub in v.subviews) [self collectView:sub depth:depth + 1];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.filterClass) return _allRows.count;
    return _groupNames.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Row"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Row"];

    if (self.filterClass) {
        // 二级：该类的具体实例，显示 frame/深度
        DHViewRow *row = _allRows[indexPath.row];
        CGRect f = row.view.frame;
        cell.textLabel.text = [NSString stringWithFormat:@"↳ %.0f,%.0f  %.0fx%.0f", f.origin.x, f.origin.y, f.size.width, f.size.height];
        cell.textLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        // 一级：类名 + 实例数
        NSString *cls = _groupNames[indexPath.row];
        NSArray *arr = _groups[cls];
        cell.textLabel.text = cls;
        cell.textLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld 个实例", (long)arr.count];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (self.filterClass) {
        // 二级实例 → 详情
        DHViewRow *row = _allRows[indexPath.row];
        if (!row.view) { [self toast:@"视图已释放"]; return; }
        [self showDetailForView:row.view];
        return;
    }

    // 一级类名 → push 二级
    NSString *cls = _groupNames[indexPath.row];
    DHViewInspectorVC *vc = [DHViewInspectorVC new];
    vc.filterClass = cls;
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - 点选识别

- (void)startPick {
    // 先 dismiss 整个调试模态界面，露出测试App，再由独立蒙版窗口接管点击
    UIViewController *top = self;
    while (top.presentingViewController) top = top.presentingViewController;
    [top dismissViewControllerAnimated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self presentPickMask];
        });
    }];
}

- (void)presentPickMask {
    UIWindow *bottom = [DHViewInspectorVC dhKeyWindow];
    UIWindow *mask = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    mask.windowLevel = UIWindowLevelAlert + 2;
    mask.backgroundColor = [UIColor clearColor];
    DHPickMaskVC *pvc = [DHPickMaskVC new];
    pvc.bottomWindow = bottom;
    mask.rootViewController = pvc;
    mask.hidden = NO;
    self.pickWindow = mask;
}

#pragma mark - 详情 / 隐藏恢复

- (void)showDetailForView:(UIView *)v {
    NSMutableString *info = [NSMutableString string];
    [info appendFormat:@"类名：%@\n", NSStringFromClass([v class])];
    [info appendFormat:@"frame：%@\n", NSStringFromCGRect(v.frame)];
    [info appendFormat:@"bounds：%@\n", NSStringFromCGRect(v.bounds)];
    [info appendFormat:@"hidden：%@  alpha：%.2f\n", v.hidden ? @"YES" : @"NO", v.alpha];

    NSMutableArray *chain = [NSMutableArray new];
    UIView *p = v.superview;
    while (p) { [chain addObject:NSStringFromClass([p class])]; p = p.superview; }
    [info appendFormat:@"父链：%@\n", [chain componentsJoinedByString:@" → "]];

    UIResponder *resp = v.nextResponder;
    while (resp && ![resp isKindOfClass:[UIViewController class]]) resp = resp.nextResponder;
    if (resp) [info appendFormat:@"所属VC：%@\n", NSStringFromClass([resp class])];

    if ([v isKindOfClass:[UIButton class]]) {
        UIButton *b = (UIButton *)v;
        NSString *title = [b titleForState:UIControlStateNormal] ?: @"";
        [info appendFormat:@"按钮标题：%@\n", title];
    }

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"视图详情" message:info preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"隐藏该视图" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        v.hidden = YES;
        [weakSelf reloadTree];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"恢复该视图" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        v.hidden = NO;
        [weakSelf reloadTree];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)toast:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:a animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [a dismissViewControllerAnimated:YES completion:nil]; });
    }];
}

@end
