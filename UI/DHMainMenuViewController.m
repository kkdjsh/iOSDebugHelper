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
        [self showAlert:@"智能扫描助手" message:@"FLEX集成中，即将开放"];
    } else if ([action isEqualToString:@"openDataMonitor"]) {
        [self showAlert:@"数据分析" message:@"FLEX集成中，即将开放"];
    } else if ([action isEqualToString:@"openPatches"]) {
        DHLogInfo(@"打开补丁管理");
    } else if ([action isEqualToString:@"openNetworkRules"]) {
        DHLogInfo(@"打开网络规则");
    } else if ([action isEqualToString:@"openGlobalScan"]) {
        [self runGlobalScan];
    } else if ([action isEqualToString:@"openLogs"]) {
        [self showLogs];
    } else if ([action isEqualToString:@"openAbout"]) {
        [self showAlert:@"关于本工具" message:@"iOS调试助手 v1.0.0\n基于FLEX框架二次开发\n仅供学习研究使用"];
    } else if ([action isEqualToString:@"openHelp"]) {
        [self showAlert:@"使用说明" message:@"1. 悬浮球打开主菜单\n2. 智能扫描：搜索VIP/广告相关类\n3. 网络规则：修改API响应\n4. 补丁管理：持久化Hook配置\n5. 数据分析：查看网络请求和AES密钥"];
    } else if ([action isEqualToString:@"openVersion"]) {
        [self showAlert:@"版本信息" message:@"版本: 1.0.0\n架构: arm64/arm64e\n最低系统: iOS 14.0"];
    } else if ([action isEqualToString:@"resetConfig"]) {
        [self resetAllConfig];
    }
}

- (void)runGlobalScan {
    [DHLogManager sharedManager];
    [self showAlert:@"全局扫描" message:@"开始扫描已加载类...\n结果将在扫描完成后显示"];
    [[DHAdScanner sharedScanner] scanAllClassesWithProgress:^(NSUInteger cur, NSUInteger total) {
        DHLogDebug(@"扫描进度: %lu/%lu", (unsigned long)cur, (unsigned long)total);
    } completion:^(NSArray<DHScannerResult *> *results) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showAlert:@"扫描完成" message:[NSString stringWithFormat:@"共扫描到 %lu 条结果", (unsigned long)results.count]];
        });
    }];
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

- (void)showAlert:(NSString *)title message:(NSString *)msg {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
