#import "DHViewInspectorVC.h"
#import "DHAIManager.h"

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

// 被移除视图的可恢复栈：parent(弱) + 原下标 + view(弱)
static NSMutableArray *gRemovedStack(void) {
    static NSMutableArray *stack;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ stack = [NSMutableArray new]; });
    return stack;
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
    // 移除该视图：真正从父视图删掉，触发自动布局让下方上移
    [sheet addAction:[UIAlertAction actionWithTitle:@"移除该视图（下方自动上移）" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        UIView *parent = v.superview;
        NSInteger idx = parent ? [parent.subviews indexOfObject:v] : NSNotFound;
        if (parent) [gRemovedStack() addObject:@{
            @"parent": [NSValue valueWithNonretainedObject:parent],
            @"index": @(idx),
            @"view": [NSValue valueWithNonretainedObject:v],
        }];
        [v removeFromSuperview];
        [parent setNeedsLayout];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"恢复全部已移除视图" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSArray *stack = [gRemovedStack() copy];
        for (NSDictionary *rec in stack.reverseObjectEnumerator) {
            UIView *parent = [(NSValue *)rec[@"parent"] nonretainedObjectValue];
            UIView *view = [(NSValue *)rec[@"view"] nonretainedObjectValue];
            NSInteger idx = [rec[@"index"] integerValue];
            if (parent && view) {
                if (idx != NSNotFound && idx <= (NSInteger)parent.subviews.count) {
                    [parent insertSubview:view atIndex:idx];
                } else {
                    [parent addSubview:view];
                }
            }
        }
        [gRemovedStack() removeAllObjects];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}
@end

@interface DHViewInspectorVC () <UISearchBarDelegate>
@property (nonatomic, copy) NSString *filterClass; // 二级：只看这个类
@property (nonatomic, strong) UIWindow *pickWindow;
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic, strong) NSArray *displayNames; // 一级过滤后类名
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

        // 搜索框
        UISearchBar *sb = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 52)];
        sb.placeholder = @"搜索类名 / 中文翻译";
        sb.delegate = self;
        self.tableView.tableHeaderView = sb;

        // AI翻译类名按钮 + 已移除视图入口
        UIBarButtonItem *aiBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"sparkles"] style:UIBarButtonItemStylePlain target:self action:@selector(translateVisibleClasses)];
        UIBarButtonItem *removedBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash"] style:UIBarButtonItemStylePlain target:self action:@selector(showRemovedList)];
        self.navigationItem.rightBarButtonItems = @[
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reloadTree)],
            aiBtn,
            removedBtn,
        ];
    } else {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reloadTree)];
    }
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
        NSArray *all = [[g allKeys] sortedArrayUsingSelector:@selector(compare:)];
        _groupNames = all;
        [self applySearchFilter];
    }
    [self.tableView reloadData];
}

// 一级：按搜索词过滤类名（类名原文 + AI中文翻译）
- (void)applySearchFilter {
    if (self.filterClass) { self.displayNames = nil; return; }
    NSString *k = self.searchText.lowercaseString;
    if (!k.length) { self.displayNames = _groupNames; return; }
    NSMutableArray *out = [NSMutableArray new];
    for (NSString *cls in _groupNames) {
        if ([cls.lowercaseString containsString:k]) { [out addObject:cls]; continue; }
        NSString *zh = [DHAIManager translationForKey:[@"view::" stringByAppendingString:cls]];
        if (zh.length && [zh containsString:self.searchText]) [out addObject:cls];
    }
    self.displayNames = out;
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.searchText = searchText;
    [self applySearchFilter];
    [self.tableView reloadData];
}

// AI翻译当前视图类名（view::类名 缓存，独立于方法/类名翻译）
- (void)translateVisibleClasses {
    DHAIConfig *cfg = [DHAIManager sharedManager].config;
    if (!cfg.apiKey.length) { [self toast:@"请先在 AI 配置中心填写 API Key"]; return; }
    if (!cfg.apiURL.length) { [self toast:@"请先在 AI 配置中心填写 API 地址"]; return; }

    NSMutableArray *need = [NSMutableArray new];
    for (NSString *cls in _groupNames) {
        if (![DHAIManager translationForKey:[@"view::" stringByAppendingString:cls]].length) [need addObject:cls];
    }
    if (need.count == 0) { [self toast:@"视图类名都已翻译"]; return; }
    [self toast:[NSString stringWithFormat:@"正在翻译 %ld 个视图类…", (long)need.count]];

    NSString *apiURL = cfg.apiURL;
    if (![apiURL hasSuffix:@"/chat/completions"]) apiURL = [apiURL stringByAppendingString:@"/chat/completions"];
    NSDictionary *body = @{
        @"model": cfg.model ?: @"deepseek-chat",
        @"messages": @[
            @{@"role": @"system", @"content": @"你是iOS界面分析助手。输入是UIView子类类名，把它翻译成简洁中文（说明该视图大致用途/是什么界面元素）。严格返回JSON对象，key是原类名，value是中文，不要输出其他内容。"},
            @{@"role": @"user", @"content": [need componentsJoinedByString:@"\n"]},
        ],
        @"temperature": @0.3,
        @"response_format": @{@"type": @"json_object"},
    };
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:apiURL]];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", cfg.apiKey] forHTTPHeaderField:@"Authorization"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    req.timeoutInterval = 150;

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        if (error) { dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf toast:@"视图类翻译失败：网络错误"]; }); return; }
        NSError *jsonErr;
        id outer = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        if (jsonErr || ![outer isKindOfClass:[NSDictionary class]]) { dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf toast:@"视图类翻译失败：返回格式错误"]; }); return; }
        id contentRaw = outer[@"choices"][0][@"message"][@"content"];
        if (![contentRaw isKindOfClass:[NSString class]]) { dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf toast:@"视图类翻译失败：无内容"]; }); return; }
        NSError *pErr;
        id map = [NSJSONSerialization JSONObjectWithData:[(NSString *)contentRaw dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&pErr];
        if (pErr || ![map isKindOfClass:[NSDictionary class]]) { dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf toast:@"视图类翻译失败：解析JSON失败"]; }); return; }
        NSInteger ok = 0;
        for (NSString *cls in need) {
            id zh = map[cls];
            if ([zh isKindOfClass:[NSString class]] && [(NSString *)zh length]) {
                [DHAIManager setTranslation:zh forKey:[@"view::" stringByAppendingString:cls]];
                ok++;
            }
        }
        [DHAIManager flushCache];
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf applySearchFilter];
            [weakSelf.tableView reloadData];
            [weakSelf toast:[NSString stringWithFormat:@"视图类翻译完成：%ld/%ld", (long)ok, (long)need.count]];
        });
    }];
    [task resume];
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
    return self.displayNames.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Row"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Row"];

    if (self.filterClass) {
        // 二级：该类的具体实例，显示内容文字/位置/状态，右侧缩略图
        DHViewRow *row = _allRows[indexPath.row];
        UIView *v = row.view;
        CGRect f = v.frame;
        NSString *txt = [self dhTextInView:v];
        NSString *prefix = v.hidden ? @"[已隐藏] " : @"";
        if (txt.length) {
            cell.textLabel.text = [NSString stringWithFormat:@"%@“%@”", prefix, txt];
        } else {
            cell.textLabel.text = [NSString stringWithFormat:@"%@位置(%.0f, %.0f) · 尺寸 %.0f × %.0f", prefix, f.origin.x, f.origin.y, f.size.width, f.size.height];
        }
        cell.textLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        cell.textLabel.textColor = v.hidden ? [UIColor systemGrayColor] : [UIColor labelColor];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"位置(%.0f,%.0f) %.0f×%.0f · hidden:%@ α:%.2f", f.origin.x, f.origin.y, f.size.width, f.size.height, v.hidden ? @"隐藏" : @"显示", v.alpha];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:11];

        // 右侧小缩略图；抓不到内容时显示灰色占位+类名缩写
        UIView *acc = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 72, 48)];
        UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(0, 4, 60, 40)];
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.layer.borderColor = [UIColor lightGrayColor].CGColor;
        iv.layer.borderWidth = 0.5;
        UIImage *thumb = [self dhThumbnailOfView:v];
        if (thumb) {
            iv.image = thumb;
        } else {
            iv.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1];
            UILabel *ph = [[UILabel alloc] initWithFrame:iv.bounds];
            NSString *cls = NSStringFromClass([v class]);
            ph.text = cls.length > 3 ? [cls substringFromIndex:cls.length - 3] : cls;
            ph.font = [UIFont systemFontOfSize:9];
            ph.textColor = [UIColor systemGrayColor];
            ph.textAlignment = NSTextAlignmentCenter;
            [iv addSubview:ph];
        }
        [acc addSubview:iv];
        UIImageView *arrow = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
        arrow.tintColor = [UIColor systemGray2Color];
        arrow.frame = CGRectMake(62, 18, 8, 12);
        [acc addSubview:arrow];
        cell.accessoryView = acc;

        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressInstance:)];
        cell.gestureRecognizers = @[lp];
    } else {
        // 一级：类名（AI中文翻译）+ 实例数
        NSString *cls = self.displayNames[indexPath.row];
        NSArray *arr = _groups[cls];
        NSString *zh = [DHAIManager translationForKey:[@"view::" stringByAppendingString:cls]];
        cell.textLabel.text = zh.length ? [NSString stringWithFormat:@"%@（%@）", cls, zh] : cls;
        cell.textLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        cell.textLabel.textColor = [UIColor labelColor];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld 个实例", (long)arr.count];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessoryView = nil;
        cell.gestureRecognizers = nil;
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
    NSString *cls = self.displayNames[indexPath.row];
    DHViewInspectorVC *vc = [DHViewInspectorVC new];
    vc.filterClass = cls;
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - 点选识别

// 静态兜住蒙版窗口，避免 dismiss 调试界面后被释放
static UIWindow *gPickMaskWindow;

- (void)startPick {
    // dismiss 前先把蒙版窗口建好（独立于调试VC），dismiss 露出App后再显示
    UIWindow *bottom = [DHViewInspectorVC dhKeyWindow];
    UIWindow *mask = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    mask.windowLevel = UIWindowLevelAlert + 2;
    mask.backgroundColor = [UIColor clearColor];
    DHPickMaskVC *pvc = [DHPickMaskVC new];
    pvc.bottomWindow = bottom;
    mask.rootViewController = pvc;
    gPickMaskWindow = mask;

    UIViewController *top = self;
    while (top.presentingViewController) top = top.presentingViewController;
    [top dismissViewControllerAnimated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            mask.hidden = NO;
        });
    }];
}

#pragma mark - 详情 / 隐藏恢复

// 高亮定位浮层
static UIWindow *gHighlightWin;

- (void)longPressInstance:(UILongPressGestureRecognizer *)lp {
    if (lp.state != UIGestureRecognizerStateBegan) return;
    UITableViewCell *cell = (UITableViewCell *)lp.view;
    NSIndexPath *ip = [self.tableView indexPathForCell:cell];
    if (!ip || !self.filterClass) return;
    DHViewRow *row = _allRows[ip.row];
    if (!row.view) { [self toast:@"视图已释放"]; return; }
    UIView *v = row.view;

    NSString *cls = NSStringFromClass([v class]);
    NSString *zh = [DHAIManager translationForKey:[@"view::" stringByAppendingString:cls]];
    NSString *msg = zh.length ? [NSString stringWithFormat:@"%@（%@）", cls, zh] : cls;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"视图操作" message:msg preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"高亮显示该UI（屏幕框出）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self highlightView:v];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"查看详情" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self showDetailForView:v];
    }]];
    // 手动微调位置，每次 10pt，可重复长按继续调
    [sheet addAction:[UIAlertAction actionWithTitle:@"⬆ 上移 10" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self dhMoveView:v dx:0 dy:-10]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"⬇ 下移 10" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self dhMoveView:v dx:0 dy:10]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"⬅ 左移 10" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self dhMoveView:v dx:-10 dy:0]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"➡ 右移 10" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self dhMoveView:v dx:10 dy:0]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"移除该视图（下方兄弟上移）" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        UIView *parent = v.superview;
        CGFloat topY = v.frame.origin.y, h = v.frame.size.height;
        NSInteger idx = parent ? [parent.subviews indexOfObject:v] : NSNotFound;
        if (parent) [gRemovedStack() addObject:@{
            @"parent": [NSValue valueWithNonretainedObject:parent],
            @"index": @(idx),
            @"view": [NSValue valueWithNonretainedObject:v],
        }];
        [v removeFromSuperview];
        [self dhShiftSiblingsUpIn:parent fromY:topY height:h];
        [self reloadTree];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)dhMoveView:(UIView *)v dx:(CGFloat)dx dy:(CGFloat)dy {
    CGRect f = v.frame;
    f.origin.x += dx;
    f.origin.y += dy;
    v.frame = f;
    [v.superview setNeedsLayout];
    [self reloadTree];
}

// 已移除视图列表：单项恢复 / 恢复全部
- (void)showRemovedList {
    NSArray *stack = [gRemovedStack() copy];
    NSMutableArray *alive = [NSMutableArray new];
    for (NSDictionary *rec in stack) {
        UIView *view = [(NSValue *)rec[@"view"] nonretainedObjectValue];
        if (view) [alive addObject:rec];
    }
    if (alive.count == 0) { [self toast:@"没有已移除的视图"]; return; }

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"已移除视图" message:[NSString stringWithFormat:@"共 %ld 项", (long)alive.count] preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *rec in alive) {
        UIView *view = [(NSValue *)rec[@"view"] nonretainedObjectValue];
        NSString *label = NSStringFromClass([view class]);
        [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"恢复 %@", label] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [self dhRestoreRecord:rec];
            [self reloadTree];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"恢复全部" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        for (NSDictionary *rec in alive.reverseObjectEnumerator) [self dhRestoreRecord:rec];
        [gRemovedStack() removeAllObjects];
        [self reloadTree];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)dhRestoreRecord:(NSDictionary *)rec {
    UIView *parent = [(NSValue *)rec[@"parent"] nonretainedObjectValue];
    UIView *view = [(NSValue *)rec[@"view"] nonretainedObjectValue];
    NSInteger idx = [rec[@"index"] integerValue];
    if (!parent || !view) return;
    if (idx != NSNotFound && idx <= (NSInteger)parent.subviews.count) {
        [parent insertSubview:view atIndex:idx];
    } else {
        [parent addSubview:view];
    }
    [gRemovedStack() removeObject:rec];
    [parent setNeedsLayout];
}

// 退出调试界面露出App，用独立浮层把目标视图在屏幕上红框框出
- (void)highlightView:(UIView *)v {
    NSString *clsName = NSStringFromClass([v class]);

    UIViewController *top = self;
    while (top.presentingViewController) top = top.presentingViewController;
    [top dismissViewControllerAnimated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindow *key = [DHViewInspectorVC dhKeyWindow];
            [v layoutIfNeeded];
            CGRect r = [v convertRect:v.bounds toView:key];
            if (CGRectIsEmpty(r)) return;

            if (gHighlightWin) gHighlightWin.hidden = YES;
            UIWindow *hw = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
            hw.windowLevel = UIWindowLevelAlert + 3;
            hw.backgroundColor = [UIColor clearColor];
            hw.rootViewController = [UIViewController new];

            UIView *box = [[UIView alloc] initWithFrame:r];
            box.layer.borderColor = [UIColor systemRedColor].CGColor;
            box.layer.borderWidth = 3;
            box.backgroundColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.15];
            [hw addSubview:box];

            // 标签贴在框内顶部，避免视觉上把框顶高
            UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(r.origin.x, r.origin.y, MIN(r.size.width, 220), 20)];
            lb.text = clsName;
            lb.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
            lb.textColor = [UIColor whiteColor];
            lb.backgroundColor = [UIColor colorWithRed:0.85 green:0 blue:0 alpha:0.85];
            lb.textAlignment = NSTextAlignmentCenter;
            [hw addSubview:lb];

            gHighlightWin = hw;
            hw.hidden = NO;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                gHighlightWin.hidden = YES;
            });
        });
    }];
}

- (void)showDetailForView:(UIView *)v {
    NSMutableString *info = [NSMutableString string];
    [info appendFormat:@"类名：%@\n", NSStringFromClass([v class])];
    [info appendFormat:@"frame：%@\n", NSStringFromCGRect(v.frame)];
    [info appendFormat:@"bounds：%@\n", NSStringFromCGRect(v.bounds)];
    [info appendFormat:@"hidden：%@  alpha：%.2f\n", v.hidden ? @"YES" : @"NO", v.alpha];

    // 代码标识：cell复用标识 / 按钮监听方法名
    if ([v isKindOfClass:[UITableViewCell class]]) {
        NSString *rid = [(UITableViewCell *)v reuseIdentifier];
        if (rid.length) [info appendFormat:@"复用标识：%@\n", rid];
    }
    if ([v isKindOfClass:[UIButton class]]) {
        UIButton *b = (UIButton *)v;
        NSString *title = [b titleForState:UIControlStateNormal] ?: @"";
        [info appendFormat:@"按钮标题：%@\n", title];
        NSMutableArray *selectors = [NSMutableArray new];
        for (id t in b.allTargets) {
            NSArray *acts = [b actionsForTarget:t forControlEvent:UIControlEventTouchUpInside];
            for (NSString *s in acts) { if (s.length && ![selectors containsObject:s]) [selectors addObject:s]; }
        }
        if (selectors.count) [info appendFormat:@"点击方法：%@\n", [selectors componentsJoinedByString:@", "]];
    }

    NSMutableArray *chain = [NSMutableArray new];
    UIView *p = v.superview;
    while (p) { [chain addObject:NSStringFromClass([p class])]; p = p.superview; }
    [info appendFormat:@"父链：%@\n", [chain componentsJoinedByString:@" → "]];

    UIResponder *resp = v.nextResponder;
    while (resp && ![resp isKindOfClass:[UIViewController class]]) resp = resp.nextResponder;
    if (resp) [info appendFormat:@"所属VC：%@\n", NSStringFromClass([resp class])];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"视图详情" message:info preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"移除该视图（下方兄弟上移）" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        UIView *parent = v.superview;
        CGFloat topY = v.frame.origin.y, h = v.frame.size.height;
        NSInteger idx = parent ? [parent.subviews indexOfObject:v] : NSNotFound;
        if (parent) [gRemovedStack() addObject:@{
            @"parent": [NSValue valueWithNonretainedObject:parent],
            @"index": @(idx),
            @"view": [NSValue valueWithNonretainedObject:v],
        }];
        [v removeFromSuperview];
        [weakSelf dhShiftSiblingsUpIn:parent fromY:topY height:h];
        [weakSelf reloadTree];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"仅隐藏（保留占位）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
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

// 移除后把父视图中位于其下方的兄弟整体上移一个被移除高度
- (void)dhShiftSiblingsUpIn:(UIView *)parent fromY:(CGFloat)topY height:(CGFloat)h {
    if (!parent || h <= 0) return;
    for (UIView *sib in parent.subviews) {
        if (sib.frame.origin.y >= topY - 0.5) {
            CGRect f = sib.frame;
            f.origin.y -= h;
            sib.frame = f;
        }
    }
    [parent setNeedsLayout];
}

// 递归提取视图内可见文字（UILabel / UIButton 标题）
- (NSString *)dhTextInView:(UIView *)v {
    NSMutableArray *parts = [NSMutableArray new];
    NSMutableSet *seen = [NSMutableSet new];
    [self dhCollectText:v into:parts seen:seen];
    return [parts componentsJoinedByString:@" · "];
}
- (void)dhCollectText:(UIView *)v into:(NSMutableArray *)parts seen:(NSMutableSet *)seen {
    if (!v) return;
    if ([v isKindOfClass:[UILabel class]]) {
        NSString *t = [(UILabel *)v text];
        if (t.length && ![seen containsObject:t]) { [seen addObject:t]; [parts addObject:t]; }
    } else if ([v isKindOfClass:[UIButton class]]) {
        NSString *t = [(UIButton *)v titleForState:UIControlStateNormal];
        if (t.length && ![seen containsObject:t]) { [seen addObject:t]; [parts addObject:t]; }
    }
    for (UIView *sub in v.subviews) [self dhCollectText:sub into:parts seen:seen];
}

// 渲染该视图为小缩略图
- (UIImage *)dhThumbnailOfView:(UIView *)v {
    if (!v || CGRectIsEmpty(v.bounds)) return nil;
    BOOL wasHidden = v.hidden;
    v.hidden = NO; // 隐藏视图临时显示以便渲染缩略图
    CGSize size = CGSizeMake(60, 40);
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGFloat sx = size.width / v.bounds.size.width;
        CGFloat sy = size.height / v.bounds.size.height;
        CGContextScaleCTM(ctx.CGContext, sx, sy);
        // 优先用层级合成快照（能抓到真实渲染内容），失败再退回图层绘制
        if (![v drawViewHierarchyInRect:v.bounds afterScreenUpdates:YES]) {
            [v.layer renderInContext:ctx.CGContext];
        }
    }];
    v.hidden = wasHidden;
    return img;
}

- (void)toast:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:a animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [a dismissViewControllerAnimated:YES completion:nil]; });
    }];
}

@end
