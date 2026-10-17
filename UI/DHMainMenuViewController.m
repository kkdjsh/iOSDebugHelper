//
//  DHMainMenuViewController.m
//  iOSDebugHelper
//  主菜单 - 删除JS脚本订阅、官网、TG频道入口
//

#import "DHMainMenuViewController.h"
#import "DHLogManager.h"
#import "DHAdScanner.h"
#import "DHAIManager.h"
#import "DHHookManager.h"
#import "DHRuleManager.h"
#import "DHInterceptRule.h"
#import "DHCryptManager.h"

#pragma mark - 通用列表控制器
@interface DHSimpleListVC : UITableViewController
@property (nonatomic, copy) NSArray *items;
@property (nonatomic, copy) NSString *(^formatBlock)(id obj);
@property (nonatomic, copy) void (^selectBlock)(id obj, NSIndexPath *idx);
@end

@implementation DHSimpleListVC
- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.items.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:ip];
    id obj = self.items[ip.row];
    c.textLabel.text = self.formatBlock ? self.formatBlock(obj) : [obj description];
    c.textLabel.numberOfLines = 0;
    c.textLabel.font = [UIFont systemFontOfSize:12];
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if (self.selectBlock) self.selectBlock(self.items[ip.row], ip);
}
@end

#pragma mark - 补丁管理控制器
@interface DHPatchListVC : UITableViewController
@end
@implementation DHPatchListVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"补丁管理";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addHook)];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return [DHHookManager sharedManager].savedHooks.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:ip];
    DHHookInfo *h = [DHHookManager sharedManager].savedHooks[ip.row];
    NSString *retStr;
    switch (h.returnType) {
        case DHHookReturnTrue: retStr = @"返回TRUE"; break;
        case DHHookReturnFalse: retStr = @"返回FALSE"; break;
        case DHHookReturnNil: retStr = @"返回nil"; break;
        case DHHookReturnZero: retStr = @"返回0"; break;
        case DHHookReturnCustomString: retStr = [NSString stringWithFormat:@"返回\"%@\"", h.customValue ?: @""]; break;
        case DHHookReturnCustomNumber: retStr = [NSString stringWithFormat:@"返回%@", h.customValue ?: @0]; break;
        default: retStr = @""; break;
    }
    c.textLabel.text = [NSString stringWithFormat:@"%@[%@ %@]\n→ %@", h.isClassMethod ? @"+" : @"-", h.className, h.selectorName, retStr];
    c.textLabel.font = [UIFont systemFontOfSize:11];
    c.textLabel.numberOfLines = 2;
    // 开关
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = h.enabled;
    sw.tag = ip.row;
    [sw addTarget:self action:@selector(switchToggled:) forControlEvents:UIControlEventValueChanged];
    c.accessoryView = sw;
    return c;
}
- (void)switchToggled:(UISwitch *)sw {
    DHHookInfo *h = [DHHookManager sharedManager].savedHooks[sw.tag];
    [[DHHookManager sharedManager] toggleHook:h];
    [self.tableView reloadData];
}
- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)e forRowAtIndexPath:(NSIndexPath *)ip {
    if (e == UITableViewCellEditingStyleDelete) {
        DHHookInfo *h = [DHHookManager sharedManager].savedHooks[ip.row];
        [[DHHookManager sharedManager] removeHook:h];
        [t deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}
- (NSArray *)tableView:(UITableView *)t editActionsForRowAtIndexPath:(NSIndexPath *)ip {
    DHHookInfo *h = [DHHookManager sharedManager].savedHooks[ip.row];
    UITableViewRowAction *edit = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleNormal title:@"编辑" handler:^(UITableViewRowAction *a, NSIndexPath *idx) {
        [self editHook:h];
    }];
    UITableViewRowAction *del = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDestructive title:@"删除" handler:^(UITableViewRowAction *a, NSIndexPath *idx) {
        [[DHHookManager sharedManager] removeHook:h];
        [t deleteRowsAtIndexPaths:@[idx] withRowAnimation:UITableViewRowAnimationAutomatic];
    }];
    return @[del, edit];
}
- (void)editHook:(DHHookInfo *)h {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"编辑Hook" message:@"修改返回值类型" preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *title in @[@"返回TRUE",@"返回FALSE",@"返回nil",@"返回0",@"自定义字符串",@"自定义数字"]) {
        [a addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
            if ([title isEqualToString:@"返回TRUE"]) h.returnType = DHHookReturnTrue;
            else if ([title isEqualToString:@"返回FALSE"]) h.returnType = DHHookReturnFalse;
            else if ([title isEqualToString:@"返回nil"]) h.returnType = DHHookReturnNil;
            else if ([title isEqualToString:@"返回0"]) h.returnType = DHHookReturnZero;
            else if ([title isEqualToString:@"自定义字符串"]) h.returnType = DHHookReturnCustomString;
            else h.returnType = DHHookReturnCustomNumber;
            [[DHHookManager sharedManager] saveHooks];
            [self.tableView reloadData];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)addHook {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"添加Hook" message:@"输入 类名/方法名" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = @"类名 e.g. VipManager"; }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = @"方法名 e.g. isVip"; }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = @"返回值: true/false/nil/0"; f.text = @"true"; }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"添加" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        NSString *cls = a.textFields[0].text;
        NSString *sel = a.textFields[1].text;
        NSString *ret = a.textFields[2].text.lowercaseString;
        if (!cls.length || !sel.length) return;
        DHHookInfo *h = [DHHookInfo new];
        h.className = cls;
        h.selectorName = sel;
        h.isClassMethod = NO;
        if ([ret isEqualToString:@"true"]) h.returnType = DHHookReturnTrue;
        else if ([ret isEqualToString:@"false"]) h.returnType = DHHookReturnFalse;
        else if ([ret isEqualToString:@"nil"]) h.returnType = DHHookReturnNil;
        else h.returnType = DHHookReturnZero;
        [[DHHookManager sharedManager] addHook:h];
        [self.tableView reloadData];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)tableView:(UITableView *)t accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)ip {
    NSString *code = [[DHHookManager sharedManager] exportLogosCode];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"导出Logos代码" message:code preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"复制代码" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        [UIPasteboard generalPasteboard].string = code;
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
@end

#pragma mark - 网络规则控制器
@interface DHNetworkRuleListVC : UITableViewController
@end
@implementation DHNetworkRuleListVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"网络规则";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addRule)];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [[DHRuleManager sharedManager] loadRules]; [self.tableView reloadData]; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return [DHRuleManager sharedManager].rules.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:ip];
    DHInterceptRule *r = [DHRuleManager sharedManager].rules[ip.row];
    c.textLabel.text = [NSString stringWithFormat:@"%@\n→ %@", r.urlPattern, r.patches.count ? ((DHJSONPatchItem *)r.patches[0]).keyPath : @"(无补丁)"];
    c.textLabel.font = [UIFont systemFontOfSize:11];
    c.textLabel.numberOfLines = 2;
    return c;
}
- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)e forRowAtIndexPath:(NSIndexPath *)ip {
    if (e == UITableViewCellEditingStyleDelete) {
        NSMutableArray *arr = [[DHRuleManager sharedManager].rules mutableCopy];
        [arr removeObjectAtIndex:ip.row];
        [DHRuleManager sharedManager].rules = arr;
        [[DHRuleManager sharedManager] saveRules];
        [t deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}
- (void)addRule {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"添加规则" message:@"URL正则 + JSON-Path" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = @"URL e.g. /api/User/Info"; f.text = @"/api/"; }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = @"JSONPath e.g. result.isVip"; f.text = @"result.isVip"; }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = @"值 e.g. true"; f.text = @"true"; }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"添加" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        NSString *url = a.textFields[0].text;
        NSString *path = a.textFields[1].text;
        NSString *val = a.textFields[2].text;
        if (!url.length) return;
        DHJSONPatchItem *p = [DHJSONPatchItem new];
        p.keyPath = path;
        p.valueString = val;
        DHInterceptRule *r = [DHInterceptRule new];
        r.urlPattern = url;
        r.matchType = DHMatchTypeContains;
        r.enabled = YES;
        r.patches = @[p];
        r.requestHeaderOverrides = @[];
        NSMutableArray *arr = [[DHRuleManager sharedManager].rules mutableCopy];
        [arr addObject:r];
        [DHRuleManager sharedManager].rules = arr;
        [[DHRuleManager sharedManager] saveRules];
        [self.tableView reloadData];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
@end

#pragma mark - 扫描结果控制器（带搜索、分组、Hook、区间复制、缓存）
@interface DHScanResultVC : UITableViewController <UISearchBarDelegate>
@property (nonatomic, copy) NSArray<DHScannerResult *> *allResults;
@property (nonatomic, copy) NSArray *filteredResults;      // 当前显示的扁平结果
@property (nonatomic, strong) UISearchBar *searchBar;
@end
@implementation DHScanResultVC {
    NSTimer *_searchDebounce;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"扫描结果";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"批量复制" style:UIBarButtonItemStyleDone target:self action:@selector(batchCopy)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"重新扫描" style:UIBarButtonItemStylePlain target:self action:@selector(rescan)];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];

    // 直接把搜索栏放在tableView顶部，不用UISearchController，导航按钮永远在
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    self.searchBar.placeholder = @"搜索类名或方法名...";
    self.searchBar.delegate = self;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.tableView.tableHeaderView = self.searchBar;

    self.filteredResults = self.allResults;
}

- (void)rescan {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"DHCachedScanResults"];
    [[DHAdScanner sharedScanner] scanAllClassesWithProgress:nil completion:^(NSArray<DHScannerResult *> *results) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.allResults = results;
            self.filteredResults = results;
            [self cacheResults:results];
            [self.tableView reloadData];
        });
    }];
}

- (void)cacheResults:(NSArray *)results {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:results];
    [[NSUserDefaults standardUserDefaults] setObject:data forKey:@"DHCachedScanResults"];
}

+ (NSArray *)loadCachedResults {
    NSData *data = [[NSUserDefaults standardUserDefaults] dataForKey:@"DHCachedScanResults"];
    if (data) {
        id obj = [NSKeyedUnarchiver unarchiveObjectWithData:data];
        if ([obj isKindOfClass:[NSArray class]]) return obj;
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.filteredResults.count; }

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:ip];
    DHScannerResult *r = self.filteredResults[ip.row];
    NSString *prefix = r.matchedKeyword ? [NSString stringWithFormat:@"[%@] ", r.matchedKeyword] : @"";
    c.textLabel.text = [NSString stringWithFormat:@"%@-%@\nIn Class: %@", prefix, r.methodName, r.className];
    c.textLabel.font = [UIFont systemFontOfSize:11];
    c.textLabel.numberOfLines = 2;
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return c;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    DHScannerResult *r = self.filteredResults[ip.row];
    [self showHookActionSheetForResult:r];
}

- (void)showHookActionSheetForResult:(DHScannerResult *)r {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@\nIn Class: %@", r.methodName, r.className]
                                                               message:@"选择 Hook 返回值类型"
                                                        preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"返回 TRUE (YES)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self addHook:r returnType:DHHookReturnTrue custom:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"返回 FALSE (NO)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self addHook:r returnType:DHHookReturnFalse custom:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"返回 nil" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self addHook:r returnType:DHHookReturnNil custom:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"返回 0" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self addHook:r returnType:DHHookReturnZero custom:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"返回自定义数字..." style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self promptCustomValue:r isNumber:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"返回自定义字符串..." style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self promptCustomValue:r isNumber:NO];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)promptCustomValue:(DHScannerResult *)r isNumber:(BOOL)isNum {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"输入自定义值" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = isNum ? @"数字 e.g. 1" : @"字符串 e.g. vip"; }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        NSString *val = a.textFields[0].text;
        if (!val.length) return;
        [self addHook:r returnType:isNum ? DHHookReturnCustomNumber : DHHookReturnCustomString custom:val];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)addHook:(DHScannerResult *)r returnType:(DHHookReturnType)type custom:(NSString *)custom {
    DHHookInfo *h = [DHHookInfo new];
    h.className = r.className;
    h.selectorName = r.methodName;
    h.isClassMethod = [r.methodName hasPrefix:@"(class)"];
    if (h.isClassMethod) h.selectorName = [r.methodName stringByReplacingOccurrencesOfString:@"(class) " withString:@""];
    h.returnType = type;
    h.customValue = custom;
    h.reason = [NSString stringWithFormat:@"扫描Hook: %@", r.matchedKeyword ?: @""];
    [[DHHookManager sharedManager] addHook:h];
    [self showToast:[NSString stringWithFormat:@"已添加Hook: %@", r.methodName]];
}

- (void)batchCopy {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"批量复制"
                                                            message:@"输入区间，如 1-50 或 30-50\n单数字5 = 复制前5条"
                                                     preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = [NSString stringWithFormat:@"共%lu条", (unsigned long)self.filteredResults.count]; }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"复制" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        [self doBatchCopy:a.textFields[0].text];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)doBatchCopy:(NSString *)input {
    NSInteger total = self.filteredResults.count;
    if (total == 0) { [self showToast:@"无结果"]; return; }
    NSInteger start = 0, end = 0;
    if ([input containsString:@"-"]) {
        NSArray *parts = [input componentsSeparatedByString:@"-"];
        start = [parts[0] integerValue] - 1;
        end = [parts[1] integerValue];
    } else {
        start = 0;
        end = [input integerValue];
    }
    if (start < 0) start = 0;
    if (end > total) end = total;
    if (start >= end) { [self showToast:@"区间无效"]; return; }
    NSMutableArray *lines = [NSMutableArray new];
    for (NSInteger i = start; i < end; i++) {
        DHScannerResult *r = self.filteredResults[i];
        [lines addObject:[NSString stringWithFormat:@"-%@ In Class: %@", r.methodName, r.className]];
    }
    [UIPasteboard generalPasteboard].string = [lines componentsJoinedByString:@"\n"];
    [self showToast:[NSString stringWithFormat:@"已复制第%ld-%ld条", (long)(start+1), (long)end]];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    // 防抖0.3秒，后台过滤
    [_searchDebounce invalidate];
    NSString *kw = [searchText lowercaseString];
    NSArray *all = self.allResults;
    _searchDebounce = [NSTimer scheduledTimerWithTimeInterval:0.3 repeats:NO block:^(NSTimer *t) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSArray *result;
            if (!kw.length) {
                result = all;
            } else {
                NSPredicate *pred = [NSPredicate predicateWithFormat:@"methodName CONTAINS[cd] %@ OR className CONTAINS[cd] %@", kw, kw];
                result = [all filteredArrayUsingPredicate:pred];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                self.filteredResults = result;
                [self.tableView reloadData];
            });
        });
    }];
}

- (void)showToast:(NSString *)msg {
    UIAlertController *t = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:t animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [t dismissViewControllerAnimated:YES completion:nil]; });
    }];
}
@end

#pragma mark - 主菜单
@interface DHMainMenuViewController ()
@property (nonatomic, copy) NSArray *menuSections;
@end

@implementation DHMainMenuViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"iOS调试助手";
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
    [self buildMenu];
}

- (void)buildMenu {
    self.menuSections = @[
        @{
            @"title": @"高级功能",
            @"items": @[
                @{@"title": @"智能扫描助手", @"icon": @"sparkles", @"action": @"openScanner"},
                @{@"title": @"数据分析",     @"icon": @"chart.bar.fill", @"action": @"openDataMonitor"},
                @{@"title": @"补丁管理",     @"icon": @"puzzlepiece.fill", @"action": @"openPatches"},
                @{@"title": @"网络规则",     @"icon": @"network", @"action": @"openNetworkRules"},
                @{@"title": @"全局扫描",     @"icon": @"magnifyingglass.circle.fill", @"action": @"openGlobalScan"},
                @{@"title": @"日志查看",     @"icon": @"doc.text.fill", @"action": @"openLogs"},
            ],
        },
        @{
            @"title": @"关于",
            @"items": @[
                @{@"title": @"关于本工具",   @"icon": @"info.circle", @"action": @"openAbout"},
                @{@"title": @"使用说明",     @"icon": @"questionmark.circle", @"action": @"openHelp"},
                @{@"title": @"版本信息",     @"icon": @"number", @"action": @"openVersion"},
                @{@"title": @"重置配置",     @"icon": @"gear", @"action": @"resetConfig"},
            ],
        },
    ];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.menuSections.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.menuSections[section][@"title"];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.menuSections[section][@"items"] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    NSDictionary *item = self.menuSections[indexPath.section][@"items"][indexPath.row];
    cell.textLabel.text = item[@"title"];
    cell.imageView.image = [UIImage systemImageNamed:item[@"icon"]];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = self.menuSections[indexPath.section][@"items"][indexPath.row];
    NSString *action = item[@"action"];

    if ([action isEqualToString:@"openScanner"]) {
        [self runGlobalScan];
    } else if ([action isEqualToString:@"openDataMonitor"]) {
        [self showDataMonitor];
    } else if ([action isEqualToString:@"openPatches"]) {
        DHPatchListVC *vc = [DHPatchListVC new];
        [self.navigationController pushViewController:vc animated:YES];
    } else if ([action isEqualToString:@"openNetworkRules"]) {
        DHNetworkRuleListVC *vc = [DHNetworkRuleListVC new];
        [self.navigationController pushViewController:vc animated:YES];
    } else if ([action isEqualToString:@"openGlobalScan"]) {
        [self runGlobalScan];
    } else if ([action isEqualToString:@"openLogs"]) {
        [self showLogs];
    } else if ([action isEqualToString:@"openAbout"]) {
        [self showAlert:@"关于本工具" message:@"iOS调试助手 v1.0.0\n基于FLEX框架二次开发\n仅供学习研究使用"];
    } else if ([action isEqualToString:@"openHelp"]) {
        [self showAlert:@"使用说明" message:@"1. 悬浮球打开主菜单\n2. 全局扫描：搜索VIP/广告相关类，支持批量复制\n3. 网络规则：修改API响应(预置isVip=true)\n4. 补丁管理：添加Hook修改方法返回值\n5. 数据分析：查看AES加密记录"];
    } else if ([action isEqualToString:@"openVersion"]) {
        [self showAlert:@"版本信息" message:@"版本: 1.0.0\n架构: arm64\n最低系统: iOS 14.0"];
    } else if ([action isEqualToString:@"resetConfig"]) {
        [self resetAllConfig];
    }
}

- (void)runGlobalScan {
    // 先查缓存
    NSArray *cached = [DHScanResultVC loadCachedResults];
    if (cached.count > 0) {
        DHScanResultVC *vc = [DHScanResultVC new];
        vc.allResults = cached;
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }
    // 无缓存，重新扫描
    [self showToast:@"开始扫描..."];
    [[DHAdScanner sharedScanner] scanAllClassesWithProgress:nil completion:^(NSArray<DHScannerResult *> *results) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DHScanResultVC *vc = [DHScanResultVC new];
            vc.allResults = results;
            [vc cacheResults:results];
            [self.navigationController pushViewController:vc animated:YES];
        });
    }];
}

- (void)showDataMonitor {
    NSMutableArray *items = [NSMutableArray new];
    for (DHCapturedCryptOperation *op in [DHCryptManager sharedManager].operations) {
        [items addObject:[NSString stringWithFormat:@"[%@] %@ Key=%luB IV=%@ In=%luB",
                          op.operation, op.algorithm,
                          (unsigned long)op.key.length,
                          op.iv ? @"有" : @"无",
                          (unsigned long)op.inputData.length]];
    }
    if (items.count == 0) [items addObject:@"暂无AES加密记录\n(发起网络请求后自动捕获)"];
    DHSimpleListVC *vc = [DHSimpleListVC new];
    vc.title = @"数据分析";
    vc.items = items;
    vc.formatBlock = ^NSString *(NSString *s) { return s; };
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showLogs {
    NSString *logs = [[DHLogManager sharedManager] readTodayLog];
    UITextView *tv = [[UITextView alloc] init];
    tv.text = logs ?: @"暂无日志";
    tv.editable = NO;
    tv.font = [UIFont fontWithName:@"Menlo" size:10];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:({
        UIViewController *vc = [UIViewController new];
        vc.view = tv;
        vc.title = @"日志查看";
        vc.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"清空" style:UIBarButtonItemStyleDone target:self action:@selector(clearLogs)];
        vc;
    })];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)clearLogs {
    [[DHLogManager sharedManager] clearTodayLog];
}

- (void)resetAllConfig {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重置配置" message:@"将清除所有规则、Hook、补丁和设置，确定继续？" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定重置" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"DHInterceptRules"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"DHSavedHooks"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"DHSavedPatches"];
        DHLogInfo(@"已重置全部配置");
        [self showAlert:@"完成" message:@"所有配置已重置"];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showToast:(NSString *)msg {
    UIAlertController *t = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:t animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [t dismissViewControllerAnimated:YES completion:nil]; });
    }];
}

- (void)showAlert:(NSString *)title message:(NSString *)msg {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
