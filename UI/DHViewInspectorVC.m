#import "DHViewInspectorVC.h"

// 列表行：保存视图的非保留指针 + 层级深度
@interface DHViewRow : NSObject
@property (nonatomic, weak) UIView *view;
@property (nonatomic, assign) NSInteger depth;
@end
@implementation DHViewRow
@end

@implementation DHViewInspectorVC {
    NSMutableArray<DHViewRow *> *_rows;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"视图树";
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Row"];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reloadTree)];
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

#pragma mark - 遍历视图树

- (void)reloadTree {
    _rows = [NSMutableArray new];
    UIWindow *win = [DHViewInspectorVC dhKeyWindow];
    if (win) [self collectView:win depth:0];
    [self.tableView reloadData];
}

- (void)collectView:(UIView *)v depth:(NSInteger)depth {
    if (!v) return;
    DHViewRow *row = [DHViewRow new];
    row.view = v;
    row.depth = depth;
    [_rows addObject:row];
    for (UIView *sub in v.subviews) {
        [self collectView:sub depth:depth + 1];
    }
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Row" forIndexPath:indexPath];
    DHViewRow *row = _rows[indexPath.row];
    NSMutableString *prefix = [NSMutableString string];
    for (NSInteger i = 0; i < row.depth; i++) [prefix appendString:@"  "];
    NSString *cls = NSStringFromClass([row.view class]);
    CGRect f = row.view.frame;
    cell.textLabel.text = [NSString stringWithFormat:@"%@%@  %.0fx%.0f", prefix, cls, f.size.width, f.size.height];
    cell.textLabel.font = [UIFont systemFontOfSize:12];
    cell.textLabel.numberOfLines = 1;
    cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    DHViewRow *row = _rows[indexPath.row];
    if (!row.view) { [self toast:@"视图已释放"]; return; }
    [self showDetailForView:row.view];
}

#pragma mark - 详情 / 隐藏恢复

- (void)showDetailForView:(UIView *)v {
    NSMutableString *info = [NSMutableString string];
    [info appendFormat:@"类名：%@\n", NSStringFromClass([v class])];
    [info appendFormat:@"frame：%@\n", NSStringFromCGRect(v.frame)];
    [info appendFormat:@"bounds：%@\n", NSStringFromCGRect(v.bounds)];
    [info appendFormat:@"hidden：%@  alpha：%.2f\n", v.hidden ? @"YES" : @"NO", v.alpha];

    // 父视图链
    NSMutableArray *chain = [NSMutableArray new];
    UIView *p = v.superview;
    while (p) { [chain addObject:NSStringFromClass([p class])]; p = p.superview; }
    [info appendFormat:@"父链：%@\n", [chain componentsJoinedByString:@" → "]];

    // 所属控制器
    UIResponder *resp = v.nextResponder;
    while (resp && ![resp isKindOfClass:[UIViewController class]]) resp = resp.nextResponder;
    if (resp) [info appendFormat:@"所属VC：%@\n", NSStringFromClass([resp class])];

    // 按钮公开信息：标题 + 当前事件数
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
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [a dismissViewControllerAnimated:YES completion:nil]; });
    }];
}

@end
