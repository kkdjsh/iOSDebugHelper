//
//  DHMainMenuViewController.m
//  iOSDebugHelper
//  主菜单 - 删除JS脚本订阅、官网、TG频道入口
//

#import "DHMainMenuViewController.h"
#import "DHLogManager.h"
#import "DHAdScanner.h"
#import "DHAIManager.h"
#import "DHKeepAliveManager.h"
#import "DHHookManager.h"
#import "DHRuleManager.h"
#import "DHInterceptRule.h"
#import "DHCryptManager.h"
#import "DHKeywordVC.h"
#import "DHMonitorManager.h"
#import <objc/runtime.h>

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
@property (nonatomic, copy, nullable) NSString *currentFolder; // nil=根目录
@end
@implementation DHPatchListVC

- (NSArray *)visibleHooks {
    NSMutableArray *arr = [NSMutableArray new];
    for (DHHookInfo *h in [DHHookManager sharedManager].savedHooks) {
        if (self.currentFolder) {
            if ([h.folderName isEqualToString:self.currentFolder]) [arr addObject:h];
        } else {
            if (!h.folderName.length) [arr addObject:h];
        }
    }
    return arr;
}

+ (NSString *)dhDataDir {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *d = [dir stringByAppendingPathComponent:@"iOSDebugHelper"];
    [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}

+ (NSArray *)dhLoadFolders {
    NSString *path = [[self dhDataDir] stringByAppendingPathComponent:@"folders.plist"];
    return [NSArray arrayWithContentsOfFile:path] ?: @[];
}

+ (void)dhSaveFolders:(NSArray *)folders {
    [folders writeToFile:[[self dhDataDir] stringByAppendingPathComponent:@"folders.plist"] atomically:YES];
}

- (NSArray *)folderNames {
    NSMutableSet *set = [NSMutableSet setWithArray:[DHPatchListVC dhLoadFolders]];
    for (DHHookInfo *h in [DHHookManager sharedManager].savedHooks) {
        if (h.folderName.length) [set addObject:h.folderName];
    }
    return [[set allObjects] sortedArrayUsingSelector:@selector(compare:)];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.currentFolder ?: @"补丁管理";
    if (!self.currentFolder) {
        UIBarButtonItem *addBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addMenu)];
        UIBarButtonItem *moreBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:self action:@selector(moreMenu)];
        self.navigationItem.rightBarButtonItems = @[addBtn, moreBtn];
    } else {
        UIBarButtonItem *moreBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:self action:@selector(moreMenu)];
        self.navigationItem.rightBarButtonItems = @[moreBtn];
    }
    self.tableView.rowHeight = 60;
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t {
    if (self.currentFolder) return 1;
    return 2; // section0=文件夹, section1=根目录补丁
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    if (self.currentFolder) return [self visibleHooks].count;
    if (s == 0) return [self folderNames].count;
    return [self visibleHooks].count;
}

- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    if (self.currentFolder) return nil;
    if (s == 0) return @"文件夹";
    return @"根目录补丁";
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"Cell"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];

    if (!self.currentFolder && ip.section == 0) {
        // 文件夹行
        NSString *fname = [self folderNames][ip.row];
        NSInteger count = 0;
        BOOL allOn = YES, anyOn = NO;
        for (DHHookInfo *h in [DHHookManager sharedManager].savedHooks) {
            if ([h.folderName isEqualToString:fname]) {
                count++;
                if (h.enabled) anyOn = YES; else allOn = NO;
            }
        }
        c.textLabel.text = [NSString stringWithFormat:@"📁 %@ (%ld条)", fname, (long)count];
        c.textLabel.font = [UIFont systemFontOfSize:14];
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = anyOn;
        sw.tag = 9000 + ip.row;
        [sw addTarget:self action:@selector(folderSwitchToggled:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = sw;
        return c;
    }

    // 补丁行
    DHHookInfo *h = [self visibleHooks][ip.row];
    NSString *retStr;
    switch (h.returnType) {
        case DHHookReturnTrue: retStr = @"→TRUE"; break;
        case DHHookReturnFalse: retStr = @"→FALSE"; break;
        case DHHookReturnNil: retStr = @"→nil"; break;
        case DHHookReturnVoid: retStr = @"→void"; break;
        case DHHookReturnZero: retStr = @"→0"; break;
        case DHHookReturnCustomString: retStr = [NSString stringWithFormat:@"→\"%@\"", h.customValue ?: @""]; break;
        case DHHookReturnCustomNumber: retStr = [NSString stringWithFormat:@"→%@", h.customValue ?: @0]; break;
        default: retStr = @""; break;
    }
    // 构建完整签名
    NSString *prefix = h.isClassMethod ? @"+" : @"-";
    NSString *retType = h.realReturnType ?: @"id";
    NSString *sel = h.selectorName ?: @"";
    NSString *sig;
    if ([sel containsString:@":"]) {
        NSArray *parts = [sel componentsSeparatedByString:@":"];
        NSMutableString *ms = [NSMutableString stringWithFormat:@"%@ (%@)", prefix, retType];
        NSUInteger idx = 1;
        for (NSString *p in parts) {
            if (p.length == 0) continue;
            if (idx == 1) [ms appendFormat:@"%@:(id)arg%lu", p, (unsigned long)idx];
            else [ms appendFormat:@" %@:(id)arg%lu", p, (unsigned long)idx];
            idx++;
        }
        sig = ms;
    } else {
        sig = [NSString stringWithFormat:@"%@ (%@)%@", prefix, retType, sel];
    }
    c.textLabel.text = [NSString stringWithFormat:@"%@ %@", sig, retStr];
    c.textLabel.font = [UIFont systemFontOfSize:12];
    c.textLabel.numberOfLines = 1;
    c.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    c.detailTextLabel.text = [NSString stringWithFormat:@"In Class: %@", h.className];
    c.detailTextLabel.font = [UIFont systemFontOfSize:10];
    c.detailTextLabel.textColor = [UIColor grayColor];
    c.accessoryType = UITableViewCellAccessoryNone;

    // 第三行：AI 翻译结果（从本地缓存读，缓存key只用方法名）
    NSString *cacheKey = h.selectorName;
    NSString *translation = [DHAIManager translationForKey:cacheKey];
    UILabel *thirdLabel = [c.contentView viewWithTag:999];
    if (!thirdLabel) {
        thirdLabel = [[UILabel alloc] init];
        thirdLabel.tag = 999;
        thirdLabel.font = [UIFont systemFontOfSize:10];
        thirdLabel.textColor = [UIColor systemBlueColor];
        thirdLabel.numberOfLines = 1;
        thirdLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [c.contentView addSubview:thirdLabel];
    }
    thirdLabel.text = translation;
    thirdLabel.hidden = (translation.length == 0);
    thirdLabel.frame = CGRectMake(16, 44, c.contentView.bounds.size.width - 56, 14);
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = h.enabled;
    sw.tag = ip.row;
    [sw addTarget:self action:@selector(switchToggled:) forControlEvents:UIControlEventValueChanged];
    c.accessoryView = sw;
    return c;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if (!self.currentFolder && ip.section == 0) {
        NSString *fname = [self folderNames][ip.row];
        DHPatchListVC *vc = [DHPatchListVC new];
        vc.currentFolder = fname;
        [self.navigationController pushViewController:vc animated:YES];
    }
}

- (void)switchToggled:(UISwitch *)sw {
    DHHookInfo *h = [self visibleHooks][sw.tag];
    [[DHHookManager sharedManager] toggleHook:h];
    [self.tableView reloadData];
}

- (void)folderSwitchToggled:(UISwitch *)sw {
    NSString *fname = [self folderNames][sw.tag - 9000];
    for (DHHookInfo *h in [DHHookManager sharedManager].savedHooks) {
        if ([h.folderName isEqualToString:fname]) {
            if (sw.on && !h.enabled) [[DHHookManager sharedManager] toggleHook:h];
            else if (!sw.on && h.enabled) [[DHHookManager sharedManager] toggleHook:h];
        }
    }
    [self.tableView reloadData];
}

- (NSArray *)tableView:(UITableView *)t editActionsForRowAtIndexPath:(NSIndexPath *)ip {
    if (!self.currentFolder && ip.section == 0) {
        // 文件夹左滑
        NSString *fname = [self folderNames][ip.row];
        UITableViewRowAction *rename = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleNormal title:@"重命名" handler:^(UITableViewRowAction *a, NSIndexPath *idx) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重命名文件夹" message:nil preferredStyle:UIAlertControllerStyleAlert];
            [alert addTextFieldWithConfigurationHandler:^(UITextField *f) { f.text = fname; }];
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
                NSString *newName = alert.textFields[0].text;
                if (!newName.length || [newName isEqualToString:fname]) return;
                NSMutableArray *folders = [NSMutableArray arrayWithArray:[DHPatchListVC dhLoadFolders]];
                NSUInteger i = [folders indexOfObject:fname];
                if (i != NSNotFound) folders[i] = newName;
                [DHPatchListVC dhSaveFolders:folders];
                for (DHHookInfo *h in [DHHookManager sharedManager].savedHooks) {
                    if ([h.folderName isEqualToString:fname]) h.folderName = newName;
                }
                [[DHHookManager sharedManager] saveHooks];
                [self.tableView reloadData];
            }]];
            [self presentViewController:alert animated:YES completion:nil];
        }];
        rename.backgroundColor = [UIColor systemBlueColor];
        UITableViewRowAction *del = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDestructive title:@"删除文件夹" handler:^(UITableViewRowAction *a, NSIndexPath *idx) {
            UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"确认删除" message:[NSString stringWithFormat:@"删除文件夹「%@」将同时删除内部所有补丁，确定？", fname] preferredStyle:UIAlertControllerStyleAlert];
            [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            [confirm addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *act) {
                NSMutableArray *toRemove = [NSMutableArray new];
                for (DHHookInfo *h in [DHHookManager sharedManager].savedHooks) {
                    if ([h.folderName isEqualToString:fname]) [toRemove addObject:h];
                }
                for (DHHookInfo *h in toRemove) [[DHHookManager sharedManager] removeHook:h];
                // 从文件夹列表中也删除
                NSMutableArray *folders = [NSMutableArray arrayWithArray:[DHPatchListVC dhLoadFolders]];
                [folders removeObject:fname];
                [DHPatchListVC dhSaveFolders:folders];
                [[DHHookManager sharedManager] saveHooks];
                [self.tableView reloadData];
            }]];
            [self presentViewController:confirm animated:YES completion:nil];
        }];
        return @[del, rename];
    }

    // 补丁左滑
    DHHookInfo *h = [self visibleHooks][ip.row];
    UITableViewRowAction *move = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleNormal title:@"移动" handler:^(UITableViewRowAction *a, NSIndexPath *idx) {
        [self moveHook:h];
    }];
    UITableViewRowAction *edit = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleNormal title:@"编辑" handler:^(UITableViewRowAction *a, NSIndexPath *idx) { [self editHook:h]; }];
    UITableViewRowAction *del = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDestructive title:@"删除" handler:^(UITableViewRowAction *a, NSIndexPath *idx) {
        [[DHHookManager sharedManager] removeHook:h];
        [self.tableView reloadData];
    }];
    return @[del, edit, move];
}

- (void)moveHook:(DHHookInfo *)h {
    NSArray *folders = [self folderNames];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"移动到..." message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"根目录" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        h.folderName = nil;
        [[DHHookManager sharedManager] saveHooks];
        [self.tableView reloadData];
    }]];
    for (NSString *fname in folders) {
        [sheet addAction:[UIAlertAction actionWithTitle:fname style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            h.folderName = fname;
            [[DHHookManager sharedManager] saveHooks];
            [self.tableView reloadData];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)editHook:(DHHookInfo *)h {    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"编辑Hook" message:@"修改返回值类型" preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *title in @[@"返回TRUE",@"返回FALSE",@"返回nil",@"拦截/空实现(void)",@"返回0",@"自定义字符串",@"自定义数字"]) {
        [a addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
            if ([title isEqualToString:@"返回TRUE"]) h.returnType = DHHookReturnTrue;
            else if ([title isEqualToString:@"返回FALSE"]) h.returnType = DHHookReturnFalse;
            else if ([title isEqualToString:@"返回nil"]) h.returnType = DHHookReturnNil;
            else if ([title isEqualToString:@"拦截/空实现(void)"]) h.returnType = DHHookReturnVoid;
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

- (void)addMenu {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"新建" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"新建文件夹" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) { [self addFolder]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)addFolder {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"新建文件夹" message:@"输入文件夹名称" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = @"e.g. 广告拦截"; }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        NSString *name = [a.textFields[0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!name.length) return;
        NSMutableArray *folders = [NSMutableArray arrayWithArray:[DHPatchListVC dhLoadFolders]];
        if (![folders containsObject:name]) {
            [folders addObject:name];
            [DHPatchListVC dhSaveFolders:folders];
        }
        [self.tableView reloadData];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - 导入导出

- (void)moreMenu {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"更多" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"批量管理" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self enterBatchMode]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"导出配置" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self exportMenu]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"导入配置" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self importMenu]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - 批量管理
- (void)enterBatchMode {
    self.tableView.allowsMultipleSelection = YES;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"全选" style:UIBarButtonItemStylePlain target:self action:@selector(selectAll)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(exitBatchMode)];
    
    // 加长按手势，长按cell弹出批量操作菜单
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = 0.5;
    [self.tableView addGestureRecognizer:longPress];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    CGPoint point = [gesture locationInView:self.tableView];
    NSIndexPath *ip = [self.tableView indexPathForRowAtPoint:point];
    if (!ip) return;
    if (!self.currentFolder && ip.section == 0) return; // 跳过文件夹行
    
    NSArray *selected = [self selectedHooks];
    if (selected.count == 0) {
        [self showToast:@"请先选择要操作的补丁"];
        return;
    }
    
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"已选%ld个补丁", (long)selected.count] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"批量删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { [self batchDelete]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"批量移动到文件夹" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self batchMove]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)exitBatchMode {
    self.tableView.allowsMultipleSelection = NO;
    self.navigationItem.leftBarButtonItem = nil;
    self.navigationItem.rightBarButtonItem = nil;
    // 移除底部工具栏
    for (UIView *v in self.view.subviews) {
        if ([v isKindOfClass:[UIToolbar class]]) [v removeFromSuperview];
    }
    self.tableView.contentInset = UIEdgeInsetsZero;
    [self.tableView reloadData];
}

- (void)selectAll {
    NSInteger section = self.currentFolder ? 0 : 1; // 只选补丁行，不选文件夹
    NSInteger count = [self.tableView numberOfRowsInSection:section];
    for (NSInteger i = 0; i < count; i++) {
        NSIndexPath *ip = [NSIndexPath indexPathForRow:i inSection:section];
        [self.tableView selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionNone];
    }
}

- (NSArray *)selectedHooks {
    NSArray *indexPaths = [self.tableView indexPathsForSelectedRows];
    NSMutableArray *result = [NSMutableArray new];
    for (NSIndexPath *ip in indexPaths) {
        if (!self.currentFolder && ip.section == 0) continue; // 跳过文件夹
        NSInteger row = ip.row;
        NSArray *hooks = [self visibleHooks];
        if (row < hooks.count) [result addObject:hooks[row]];
    }
    return result;
}

- (void)batchDelete {
    NSArray *selected = [self selectedHooks];
    if (selected.count == 0) {
        [self showToast:@"请先选择要删除的补丁"];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"确认删除" message:[NSString stringWithFormat:@"确定删除%ld个补丁？", (long)selected.count] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        for (DHHookInfo *h in selected) {
            [[DHHookManager sharedManager] removeHook:h];
        }
        [self showToast:[NSString stringWithFormat:@"已删除%ld个补丁", (long)selected.count]];
        [self exitBatchMode];
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)batchMove {
    NSArray *selected = [self selectedHooks];
    if (selected.count == 0) {
        [self showToast:@"请先选择要移动的补丁"];
        return;
    }
    NSArray *folders = [self folderNames];
    if (folders.count == 0) {
        [self showToast:@"没有文件夹，请先创建文件夹"];
        return;
    }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"移动到文件夹" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *fname in folders) {
        [sheet addAction:[UIAlertAction actionWithTitle:fname style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            for (DHHookInfo *h in selected) {
                h.folderName = fname;
            }
            [[DHHookManager sharedManager] saveHooks];
            [self showToast:[NSString stringWithFormat:@"已移动%ld个补丁到%@", (long)selected.count, fname]];
            [self exitBatchMode];
            [self.tableView reloadData];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)showToast:(NSString *)msg {
    UIAlertController *t = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:t animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [t dismissViewControllerAnimated:YES completion:nil]; });
    }];
}

- (NSString *)buildExportTextForHooks:(NSArray<DHHookInfo *> *)hooks folderName:(NSString *)fname {
    NSMutableString *text = [NSMutableString new];
    if (fname) [text appendFormat:@"// FolderName: %@\n", fname];
    [text appendString:@"// Generated by iOS调试助手\n\n"];

    NSMutableSet *seen = [NSMutableSet new];
    for (DHHookInfo *h in hooks) {
        NSString *sel = h.selectorName ?: @"";
        sel = [sel stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([sel hasPrefix:@"("]) sel = @"class";

        NSString *key = [NSString stringWithFormat:@"%@|%@", h.className, sel];
        if ([seen containsObject:key]) continue;
        [seen addObject:key];

        NSString *prefix = h.isClassMethod ? @"+" : @"-";
        // 容错：如果旧数据没有realReturnType，现场查runtime
        NSString *rt = h.realReturnType;
        NSUInteger argc = h.argCount;
        if (!rt || argc == 0) {
            Class cls = NSClassFromString(h.className);
            if (cls) {
                Class targetCls = h.isClassMethod ? object_getClass(cls) : cls;
                SEL sel = NSSelectorFromString(h.selectorName);
                Method m = class_getInstanceMethod(targetCls, sel);
                if (m) {
                    const char *ret = method_copyReturnType(m);
                    if (ret) {
                        NSString *s = [NSString stringWithUTF8String:ret];
                        free((void *)ret);
                        if (!rt || !rt.length) {
                            if ([s isEqualToString:@"v"]) rt = @"void";
                            else if ([s isEqualToString:@"B"] || [s isEqualToString:@"c"]) rt = @"BOOL";
                            else if ([s isEqualToString:@"i"] || [s isEqualToString:@"s"] || [s isEqualToString:@"l"] || [s isEqualToString:@"q"]) rt = @"NSInteger";
                            else if ([s isEqualToString:@"f"] || [s isEqualToString:@"d"]) rt = @"double";
                            else if ([s isEqualToString:@"#"]) rt = @"Class";
                            else rt = @"id";
                        }
                    }
                }
            }
            // 从selectorName数冒号
            argc = [[h.selectorName componentsSeparatedByString:@":"] count] - 1;
        }
        if (!rt) rt = @"id";

        // 构造完整方法签名
        NSString *signature;
        if (argc == 0) {
            signature = [NSString stringWithFormat:@"%@ (%@)%@ {", prefix, rt, sel];
        } else {
            // 有参方法：setBannerAdViewHeight: → setBannerAdViewHeight:(id)arg1
            NSMutableArray *parts = [NSMutableArray arrayWithArray:[sel componentsSeparatedByString:@":"]];
            // 去掉最后一个空元素
            if (parts.count > 0 && [(NSString *)parts.lastObject isEqualToString:@""]) [parts removeLastObject];
            NSMutableString *sig = [NSMutableString string];
            [sig appendFormat:@"%@ (%@)", prefix, rt];
            for (NSUInteger i = 0; i < parts.count; i++) {
                NSString *part = parts[i];
                if (i == 0) [sig appendFormat:@"%@:(id)arg%lu", part, (unsigned long)(i+1)];
                else [sig appendFormat:@" %@:(id)arg%lu", part, (unsigned long)(i+1)];
            }
            [sig appendString:@" {"];
            signature = sig;
        }

        // 返回值
        NSString *retVal;
        if ([rt isEqualToString:@"void"]) {
            retVal = nil; // 不写return
        } else {
            switch (h.returnType) {
                case DHHookReturnTrue: retVal = @"YES"; break;
                case DHHookReturnFalse: retVal = @"NO"; break;
                case DHHookReturnNil: retVal = @"nil"; break;
                case DHHookReturnZero: retVal = @"0"; break;
                case DHHookReturnCustomString: retVal = [NSString stringWithFormat:@"@\"%@\"", h.customValue ?: @""]; break;
                case DHHookReturnCustomNumber: retVal = [NSString stringWithFormat:@"%@", h.customValue ?: @(0)]; break;
                default: retVal = @"nil"; break;
            }
        }

        [text appendFormat:@"%%hook %@\n", h.className];
        [text appendFormat:@"%@\n", signature];
        if (retVal) [text appendFormat:@"    return %@;\n", retVal];
        [text appendString:@"}\n"];
        [text appendFormat:@"%%end\n\n"];
    }
    return text;
}

- (void)exportMenu {
    // 如果在文件夹内，直接导出当前文件夹
    if (self.currentFolder) {
        NSMutableArray *hooks = [NSMutableArray new];
        for (DHHookInfo *h in [DHHookManager sharedManager].savedHooks) {
            if ([h.folderName isEqualToString:self.currentFolder]) [hooks addObject:h];
        }
        [self exportMethod:[self buildExportTextForHooks:hooks folderName:self.currentFolder]];
        return;
    }
    // 根目录：先选导出目标
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"选择导出目标" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"全部导出" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self exportMethod:[self buildExportTextForHooks:[DHHookManager sharedManager].savedHooks folderName:nil]];
    }]];
    // 根目录补丁
    NSMutableArray *rootHooks = [NSMutableArray new];
    for (DHHookInfo *h in [DHHookManager sharedManager].savedHooks) {
        if (!h.folderName.length) [rootHooks addObject:h];
    }
    if (rootHooks.count > 0) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"仅导出根目录补丁" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [self exportMethod:[self buildExportTextForHooks:rootHooks folderName:@"根目录"]];
        }]];
    }
    // 各文件夹
    for (NSString *fname in [self folderNames]) {
        NSMutableArray *fhooks = [NSMutableArray new];
        for (DHHookInfo *h in [DHHookManager sharedManager].savedHooks) {
            if ([h.folderName isEqualToString:fname]) [fhooks addObject:h];
        }
        if (fhooks.count == 0) continue;
        [sheet addAction:[UIAlertAction actionWithTitle:fname style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [self exportMethod:[self buildExportTextForHooks:fhooks folderName:fname]];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)exportMethod:(NSString *)text {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"导出方式" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"导出为文件" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"iosdebughelper_export.txt"];
        [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSURL *url = [NSURL fileURLWithPath:path];
        UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
        [self presentViewController:avc animated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"复制到剪贴板" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [UIPasteboard generalPasteboard].string = text;
        UIAlertController *t = [UIAlertController alertControllerWithTitle:nil message:@"已复制到剪贴板" preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:t animated:YES completion:^{ dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [t dismissViewControllerAnimated:YES completion:nil]; }); }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)importMenu {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"导入配置" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"从剪贴板导入" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self importFromText:[UIPasteboard generalPasteboard].string];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)importFromText:(NSString *)text {
    if (!text.length || [text rangeOfString:@"%hook"].location == NSNotFound) {
        UIAlertController *e = [UIAlertController alertControllerWithTitle:@"格式错误" message:@"未找到%hook内容" preferredStyle:UIAlertControllerStyleAlert];
        [e addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:e animated:YES completion:nil];
        return;
    }
    // 提取文件夹名
    NSString *folderName = @"导入文件夹";
    NSRange range = [text rangeOfString:@"// FolderName: "];
    if (range.location != NSNotFound) {
        NSUInteger start = range.location + range.length;
        NSRange nl = [text rangeOfString:@"\n" options:0 range:NSMakeRange(start, text.length - start)];
        if (nl.location != NSNotFound) {
            folderName = [text substringWithRange:NSMakeRange(start, nl.location - start)];
            folderName = [folderName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
    }
    // 重名加后缀
    NSMutableArray *folders = [NSMutableArray arrayWithArray:[DHPatchListVC dhLoadFolders]];
    NSString *finalName = folderName;
    NSInteger suffix = 1;
    while ([folders containsObject:finalName]) {
        finalName = [NSString stringWithFormat:@"%@_%ld", folderName, (long)suffix++];
    }
    [folders addObject:finalName];
    [DHPatchListVC dhSaveFolders:folders];

    // 解析%hook块
    NSUInteger count = 0;
    NSScanner *sc = [NSScanner scannerWithString:text];
    while (!sc.isAtEnd) {
        NSString *hookLine = nil;
        [sc scanUpToString:@"%hook " intoString:nil];
        [sc scanString:@"%hook " intoString:nil];
        [sc scanUpToString:@"\n" intoString:&hookLine];
        hookLine = [hookLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!hookLine.length) continue;
        // 读取到%end
        NSString *body = nil;
        [sc scanUpToString:@"%end" intoString:&body];
        [sc scanString:@"%end" intoString:nil];
        if (!body.length) continue;

        // 提取方法行: - (void)methodName { 或 + (BOOL)methodName:arg1:
        NSError *err = nil;
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"([+-])\\s*\\(([^)]+)\\)([^\\{]+)\\{" options:0 error:&err];
        NSTextCheckingResult *m = [re firstMatchInString:body options:0 range:NSMakeRange(0, body.length)];
        if (!m) continue;
        NSString *sign = [body substringWithRange:[m rangeAtIndex:1]];
        NSString *returnSig = [body substringWithRange:[m rangeAtIndex:2]];
        NSString *selName = [[body substringWithRange:[m rangeAtIndex:3]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        // 提取return xxx;
        NSRegularExpression *re2 = [NSRegularExpression regularExpressionWithPattern:@"return\\s*([^;]+);" options:0 error:&err];
        NSTextCheckingResult *m2 = [re2 firstMatchInString:body options:0 range:NSMakeRange(0, body.length)];
        NSString *retVal = m2 ? [body substringWithRange:[m2 rangeAtIndex:1]] : @"nil";
        retVal = [retVal stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

        // 创建Hook
        DHHookInfo *h = [DHHookInfo new];
        h.className = hookLine;
        h.selectorName = selName;
        h.isClassMethod = [sign isEqualToString:@"+"];
        h.folderName = finalName;
        if ([retVal isEqualToString:@"YES"]) h.returnType = DHHookReturnTrue;
        else if ([retVal isEqualToString:@"NO"]) h.returnType = DHHookReturnFalse;
        else if ([retVal isEqualToString:@"nil"]) h.returnType = DHHookReturnNil;
        else if ([retVal isEqualToString:@"0"]) h.returnType = DHHookReturnZero;
        else if ([retVal hasPrefix:@"@\""]) { h.returnType = DHHookReturnCustomString; h.customValue = [retVal substringWithRange:NSMakeRange(2, retVal.length-3)]; }
        else { h.returnType = DHHookReturnCustomNumber; h.customValue = retVal; }
        h.enabled = YES;
        [[DHHookManager sharedManager] addHook:h];
        count++;
    }
    // 保存文件夹开关状态为ON
    NSMutableDictionary *folderStates = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"DHFolderSwitchStates"] mutableCopy] ?: [NSMutableDictionary new];
    folderStates[finalName] = @(YES);
    [[NSUserDefaults standardUserDefaults] setObject:folderStates forKey:@"DHFolderSwitchStates"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self.tableView reloadData];
    UIAlertController *t = [UIAlertController alertControllerWithTitle:nil message:[NSString stringWithFormat:@"成功导入 %ld 个补丁到 %@", (long)count, finalName] preferredStyle:UIAlertControllerStyleAlert];
    [t addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:t animated:YES completion:nil];
}

- (void)addHook {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"添加Hook" message:@"输入 类名/方法名/返回值" preferredStyle:UIAlertControllerStyleAlert];
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
        h.folderName = self.currentFolder; // 记录在哪个文件夹里创建的
        if ([ret isEqualToString:@"true"]) h.returnType = DHHookReturnTrue;
        else if ([ret isEqualToString:@"false"]) h.returnType = DHHookReturnFalse;
        else if ([ret isEqualToString:@"nil"]) h.returnType = DHHookReturnNil;
        else h.returnType = DHHookReturnZero;
        [[DHHookManager sharedManager] addHook:h];
        [self.tableView reloadData];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

@end

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

#pragma mark - AI 配置中心
@interface DHAIConfigVC : UITableViewController <UITextFieldDelegate, UIDocumentPickerDelegate>
@property (nonatomic, strong) UITextField *keyField;
@property (nonatomic, strong) UITextField *baseURLField;
@property (nonatomic, strong) UITextField *pathField;
@property (nonatomic, strong) UITextField *modelField;
@end

@implementation DHAIConfigVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"AI 配置中心";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(save)];

    DHAIConfig *cfg = [DHAIManager sharedManager].config;

    self.keyField = [[UITextField alloc] init];
    self.keyField.placeholder = @"sk-...";
    self.keyField.text = cfg.apiKey;
    self.keyField.secureTextEntry = YES;
    self.keyField.font = [UIFont systemFontOfSize:14];

    // 把 apiURL 拆成 baseURL + path
    NSString *fullURL = cfg.apiURL ?: @"";
    NSString *baseURL = fullURL;
    NSString *path = @"/chat/completions";
    if ([fullURL hasSuffix:@"/chat/completions"]) {
        baseURL = [fullURL substringToIndex:fullURL.length - @"/chat/completions".length];
    } else if ([fullURL containsString:@"/chat/completions"]) {
        NSRange range = [fullURL rangeOfString:@"/chat/completions"];
        baseURL = [fullURL substringToIndex:range.location];
    }

    self.baseURLField = [[UITextField alloc] init];
    self.baseURLField.placeholder = @"https://api.example.com/v1";
    self.baseURLField.text = baseURL;
    self.baseURLField.font = [UIFont systemFontOfSize:14];

    self.pathField = [[UITextField alloc] init];
    self.pathField.placeholder = @"/chat/completions";
    self.pathField.text = path;
    self.pathField.font = [UIFont systemFontOfSize:14];

    self.modelField = [[UITextField alloc] init];
    self.modelField.placeholder = @"deepseek-chat";
    self.modelField.text = cfg.model;
    self.modelField.font = [UIFont systemFontOfSize:14];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 4; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 1;
    if (s == 1) return 3;
    if (s == 2) return 1;
    return 2;
}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    if (s == 0) return @"API KEY";
    if (s == 1) return @"接口设置";
    if (s == 3) return @"翻译缓存";
    return nil;
}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if (s == 0) return @"API Key 仅保存在本地，不会上传到任何服务器。";
    if (s == 1) return @"Base URL 填到 /v1 即可，路径填 /chat/completions。两个会自动拼接成完整请求地址。";
    if (s == 3) return @"导出后可备份到文件 app，重装后导入恢复所有翻译记录。";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"AIConfigCell";
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    for (UIView *v in c.contentView.subviews) [v removeFromSuperview];
    c.textLabel.text = nil;
    c.detailTextLabel.text = nil;

    CGFloat w = [UIScreen mainScreen].bounds.size.width - 32;

    if (ip.section == 0) {
        self.keyField.frame = CGRectMake(16, 0, w - 16, 44);
        [c.contentView addSubview:self.keyField];
    } else if (ip.section == 1) {
        if (ip.row == 0) {
            self.baseURLField.frame = CGRectMake(16, 0, w - 16, 44);
            [c.contentView addSubview:self.baseURLField];
        } else if (ip.row == 1) {
            self.pathField.frame = CGRectMake(16, 0, w - 16, 44);
            [c.contentView addSubview:self.pathField];
        } else {
            self.modelField.frame = CGRectMake(16, 0, w - 16, 44);
            [c.contentView addSubview:self.modelField];
        }
    } else if (ip.section == 2) {
        c.textLabel.text = @"🧪 测试连接";
        c.textLabel.font = [UIFont systemFontOfSize:16];
        c.textLabel.textAlignment = NSTextAlignmentCenter;
        c.textLabel.textColor = [UIColor systemBlueColor];
    } else {
        if (ip.row == 0) {
            c.textLabel.text = @"📤 导出翻译缓存";
            c.textLabel.font = [UIFont systemFontOfSize:16];
            c.textLabel.textAlignment = NSTextAlignmentCenter;
            c.textLabel.textColor = [UIColor systemBlueColor];
        } else {
            c.textLabel.text = @"📥 导入翻译缓存";
            c.textLabel.font = [UIFont systemFontOfSize:16];
            c.textLabel.textAlignment = NSTextAlignmentCenter;
            c.textLabel.textColor = [UIColor systemBlueColor];
        }
    }
    return c;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 2) {
        [self testConnection];
    } else if (ip.section == 3) {
        if (ip.row == 0) {
            [self exportTranslationCache];
        } else {
            [self importTranslationCache];
        }
    }
}

- (void)exportTranslationCache {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *cachePath = [dir stringByAppendingPathComponent:@"iOSDebugHelper/translations.plist"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:cachePath]) {
        [self showToast:@"还没有翻译记录可导出"];
        return;
    }
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:cachePath];
    if (dict.count == 0) {
        [self showToast:@"还没有翻译记录可导出"];
        return;
    }
    // 导出成txt格式，更美观
    NSMutableString *text = [NSMutableString string];
    [text appendFormat:@"# 翻译缓存备份\n# 共%lu条\n\n", (unsigned long)dict.count];
    NSArray *sortedKeys = [[dict allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in sortedKeys) {
        [text appendFormat:@"%@ → %@\n", key, dict[key]];
    }
    NSString *exportPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"翻译缓存_备份.txt"];
    [text writeToFile:exportPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSURL *fileURL = [NSURL fileURLWithPath:exportPath];
    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
    [self presentViewController:activityVC animated:YES completion:nil];
}

- (void)importTranslationCache {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"导入翻译" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"从文件导入" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.data"] inMode:UIDocumentPickerModeImport];
        picker.delegate = self;
        picker.allowsMultipleSelection = NO;
        [self presentViewController:picker animated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"粘贴AI结果导入（剪贴板）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self applyImportedText:[UIPasteboard generalPasteboard].string];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

// 解析任意来源文本：AI返回的JSON字典 / 箭头txt / 带```代码围栏，返回{方法名:中文}
- (NSDictionary *)parseTranslationText:(NSString *)raw {
    if (!raw) return nil;
    NSMutableDictionary *out = [NSMutableDictionary new];
    NSString *t = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    // 剥离 ```json 代码围栏
    t = [t stringByReplacingOccurrencesOfString:@"```json" withString:@""];
    t = [t stringByReplacingOccurrencesOfString:@"```JSON" withString:@""];
    t = [t stringByReplacingOccurrencesOfString:@"```" withString:@""];

    // 1) 尝试 JSON 字典
    NSData *data = [t dataUsingEncoding:NSUTF8StringEncoding];
    NSError *je;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&je];
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (NSString *k in [(NSDictionary *)obj allKeys]) {
            NSString *v = [obj[k] isKindOfClass:[NSString class]] ? obj[k] : nil;
            if (k.length > 0 && v.length > 0) out[k] = v;
        }
        if (out.count > 0) return out;
    }

    // 2) 箭头 txt 逐行：方法名 → 中文，跳过 # 注释和空行
    NSArray *lines = [raw componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSCharacterSet *trim = [NSCharacterSet whitespaceCharacterSet];
    for (NSString *line in lines) {
        NSString *s = [line stringByTrimmingCharactersInSet:trim];
        if (s.length == 0 || [s hasPrefix:@"#"]) continue;
        NSString *sep = nil;
        for (NSString *c in @[@" → ", @"→", @"->", @" = ", @"=", @"："]) {
            if ([s rangeOfString:c].location != NSNotFound) { sep = c; break; }
        }
        if (!sep) continue;
        NSRange r = [s rangeOfString:sep];
        NSString *key = [[s substringToIndex:r.location] stringByTrimmingCharactersInSet:trim];
        NSString *val = [[s substringFromIndex:r.location + r.length] stringByTrimmingCharactersInSet:trim];
        if (key.length > 0 && val.length > 0) out[key] = val;
    }
    return out.count > 0 ? out : nil;
}

- (void)applyImportedText:(NSString *)raw {
    NSDictionary *parsed = [self parseTranslationText:raw];
    if (!parsed) { [self showToast:@"导入失败：无法识别格式（需JSON或 方法名→中文）"]; return; }
    [self applyImportedDict:parsed];
}

- (void)applyImportedDict:(NSDictionary *)dict {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *cachePath = [dir stringByAppendingPathComponent:@"iOSDebugHelper/translations.plist"];
    NSMutableDictionary *local = [NSMutableDictionary dictionaryWithContentsOfFile:cachePath] ?: [NSMutableDictionary new];
    [local addEntriesFromDictionary:dict];
    [local writeToFile:cachePath atomically:YES];
    [self showToast:[NSString stringWithFormat:@"导入成功，共%lu条翻译", (unsigned long)local.count]];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) return;
    NSURL *url = urls[0];

    // 1) 先尝试 plist 字典文件（兼容旧备份）
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfURL:url error:nil];
    if (dict) { [self applyImportedDict:dict]; return; }

    // 2) 读文本，按 JSON / 箭头txt 解析
    NSString *raw = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
    NSDictionary *parsed = [self parseTranslationText:raw];
    if (!parsed) { [self showToast:@"导入失败：文件格式错误"]; return; }
    [self applyImportedDict:parsed];
}

- (NSString *)fullAPIURL {
    NSString *base = self.baseURLField.text ?: @"";
    NSString *path = self.pathField.text ?: @"/chat/completions";
    if ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
    if (![path hasPrefix:@"/"]) path = [NSString stringWithFormat:@"/%@", path];
    return [NSString stringWithFormat:@"%@%@", base, path];
}

- (void)save {
    DHAIConfig *cfg = [DHAIManager sharedManager].config;
    cfg.apiKey = self.keyField.text ?: @"";
    cfg.apiURL = [self fullAPIURL];
    cfg.model = self.modelField.text ?: @"";
    [[DHAIManager sharedManager] saveConfig];
    [self showToast:@"配置已保存"];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)testConnection {
    NSString *url = [self fullAPIURL];
    NSString *key = self.keyField.text;
    if (!self.baseURLField.text.length) { [self showToast:@"请先填写 Base URL"]; return; }
    if (!key.length) { [self showToast:@"请先填写 API Key"]; return; }
    [self showToast:[NSString stringWithFormat:@"正在测试: %@", url]];
    NSDictionary *body = @{
        @"model": self.modelField.text.length ? self.modelField.text : @"deepseek-chat",
        @"messages": @[@{@"role": @"user", @"content": @"hi"}],
        @"max_tokens": @5,
    };
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", key] forHTTPHeaderField:@"Authorization"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    req.timeoutInterval = 15;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) { [self showToast:[NSString stringWithFormat:@"连接失败: %@", error.localizedDescription]]; return; }
            NSHTTPURLResponse *r = (NSHTTPURLResponse *)resp;
            if (r.statusCode == 200) {
                [self showToast:@"✅ 连接成功"];
            } else {
                [self showToast:[NSString stringWithFormat:@"HTTP %ld", (long)r.statusCode]];
            }
        });
    }];
    [task resume];
}

- (void)showToast:(NSString *)msg {
    if (self.presentedViewController) {
        [self.presentedViewController dismissViewControllerAnimated:YES completion:^{
            [self presentNewToast:msg];
        }];
    } else {
        [self presentNewToast:msg];
    }
}

- (void)presentNewToast:(NSString *)msg {
    UIAlertController *t = [UIAlertController alertControllerWithTitle:@"提示" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [t addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:t animated:YES completion:nil];
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
    NSInteger _searchScope; // 0=全部 1=类名 2=方法名
    BOOL _filterSystemClasses; // 默认YES
    BOOL _filterBOOLOnly;
    BOOL _filterHasArgs;
    BOOL _filterSetPrefix; // 过滤掉 set 开头的方法
    BOOL _filterVoidOnly; // 仅看 void 方法
    NSSet<NSString *> *_activeKeywords; // 闪电词库激活的关键词（普通模式）
    NSArray<NSRegularExpression *> *_activeRegexes; // 闪电词库激活的正则模式
    BOOL _filterClassMethods;
    BOOL _filterInstanceMethods;
    NSMutableSet<NSString *> *_selectedSet; // 多选选中的方法 key: className|methodName
    NSInteger _copyFormat; // 0=类名+方法名 1=仅方法名 2=仅类名
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"扫描结果";
    _filterSystemClasses = YES;
    [self setupDefaultKeywordFolders];

    // 创建自定义导航栏按钮
    // 圆形图标按钮工厂
    UIButton *(^circleBtn)(NSString*, SEL) = ^UIButton*(NSString *iconName, SEL action) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(0, 0, 32, 32);
        [b setImage:[UIImage systemImageNamed:iconName] forState:UIControlStateNormal];
        [b setTintColor:[UIColor systemBlueColor]];
        b.backgroundColor = [UIColor secondarySystemBackgroundColor];
        b.layer.cornerRadius = 16;
        b.layer.masksToBounds = YES;
        b.imageEdgeInsets = UIEdgeInsetsMake(7, 7, 7, 7);
        [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
        // 加按压动画
        [b addTarget:self action:@selector(btnTouchDown:) forControlEvents:UIControlEventTouchDown];
        [b addTarget:self action:@selector(btnTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
        return b;
    };

    // 圆角填充按钮工厂（高频功能）
    UIButton *(^pillBtn)(NSString*, SEL) = ^UIButton*(NSString *title, SEL action) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        [b setTitle:title forState:UIControlStateNormal];
        [b setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        b.backgroundColor = [UIColor colorWithRed:0.85 green:0.92 blue:1.0 alpha:1.0];
        b.layer.cornerRadius = 14;
        b.layer.masksToBounds = YES;
        b.contentEdgeInsets = UIEdgeInsetsMake(5, 12, 5, 12);
        [b sizeToFit];
        CGRect f = b.frame;
        f.size.height = 28;
        b.frame = f;
        [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
        [b addTarget:self action:@selector(btnTouchDown:) forControlEvents:UIControlEventTouchDown];
        [b addTarget:self action:@selector(btnTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
        return b;
    };

    self.tableView.rowHeight = 60;
    CGFloat w = [UIScreen mainScreen].bounds.size.width;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 52)];
    header.backgroundColor = [UIColor whiteColor];

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(4, 6, w - 90, 40)];
    self.searchBar.placeholder = @"搜索类名/方法名";
    self.searchBar.delegate = self;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    [header addSubview:self.searchBar];

    UIButton *filterBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    filterBtn.frame = CGRectMake(w - 80, 10, 76, 32);
    [filterBtn setImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"] forState:UIControlStateNormal];
    filterBtn.titleLabel.font = [UIFont systemFontOfSize:13];
    filterBtn.tag = 200;
    [filterBtn addTarget:self action:@selector(filterBtnTapped:) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:filterBtn];
    
    // 按钮放回导航栏
    UIButton *eyeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    eyeBtn.frame = CGRectMake(0, 0, 32, 32);
    [eyeBtn setImage:[UIImage systemImageNamed:@"eye.fill"] forState:UIControlStateNormal];
    [eyeBtn setTintColor:[UIColor systemBlueColor]];
    eyeBtn.backgroundColor = [UIColor secondarySystemBackgroundColor];
    eyeBtn.layer.cornerRadius = 16;
    eyeBtn.layer.masksToBounds = YES;
    eyeBtn.imageEdgeInsets = UIEdgeInsetsMake(7, 7, 7, 7);
    eyeBtn.userInteractionEnabled = YES;
    [eyeBtn addTarget:self action:@selector(startMonitorFromScan) forControlEvents:UIControlEventTouchUpInside];
    
    UIButton *sparkBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    sparkBtn.frame = CGRectMake(0, 0, 32, 32);
    [sparkBtn setImage:[UIImage systemImageNamed:@"sparkles"] forState:UIControlStateNormal];
    [sparkBtn setTintColor:[UIColor systemBlueColor]];
    sparkBtn.backgroundColor = [UIColor secondarySystemBackgroundColor];
    sparkBtn.layer.cornerRadius = 16;
    sparkBtn.layer.masksToBounds = YES;
    sparkBtn.imageEdgeInsets = UIEdgeInsetsMake(7, 7, 7, 7);
    sparkBtn.userInteractionEnabled = YES;
    [sparkBtn addTarget:self action:@selector(translateWithAI) forControlEvents:UIControlEventTouchUpInside];
    
    UIButton *boltBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    boltBtn.frame = CGRectMake(0, 0, 32, 32);
    [boltBtn setImage:[UIImage systemImageNamed:@"bolt.fill"] forState:UIControlStateNormal];
    [boltBtn setTintColor:[UIColor systemBlueColor]];
    boltBtn.backgroundColor = [UIColor secondarySystemBackgroundColor];
    boltBtn.layer.cornerRadius = 16;
    boltBtn.layer.masksToBounds = YES;
    boltBtn.imageEdgeInsets = UIEdgeInsetsMake(7, 7, 7, 7);
    boltBtn.userInteractionEnabled = YES;
    [boltBtn addTarget:self action:@selector(openKeywordMenu) forControlEvents:UIControlEventTouchUpInside];
    
    UIButton *patchBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    patchBtn.frame = CGRectMake(0, 0, 50, 28);
    [patchBtn setTitle:@"补丁" forState:UIControlStateNormal];
    [patchBtn setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    patchBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    patchBtn.backgroundColor = [UIColor colorWithRed:0.85 green:0.92 blue:1.0 alpha:1.0];
    patchBtn.layer.cornerRadius = 14;
    patchBtn.layer.masksToBounds = YES;
    patchBtn.userInteractionEnabled = YES;
    [patchBtn addTarget:self action:@selector(batchPatchMenu) forControlEvents:UIControlEventTouchUpInside];
    
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    copyBtn.frame = CGRectMake(0, 0, 50, 28);
    [copyBtn setTitle:@"复制" forState:UIControlStateNormal];
    [copyBtn setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    copyBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    copyBtn.backgroundColor = [UIColor colorWithRed:0.85 green:0.92 blue:1.0 alpha:1.0];
    copyBtn.layer.cornerRadius = 14;
    copyBtn.layer.masksToBounds = YES;
    copyBtn.userInteractionEnabled = YES;
    [copyBtn addTarget:self action:@selector(batchCopy) forControlEvents:UIControlEventTouchUpInside];
    
    UIBarButtonItem *eyeItem = [[UIBarButtonItem alloc] initWithCustomView:eyeBtn];
    UIBarButtonItem *sparkItem = [[UIBarButtonItem alloc] initWithCustomView:sparkBtn];
    UIBarButtonItem *boltItem = [[UIBarButtonItem alloc] initWithCustomView:boltBtn];
    UIBarButtonItem *patchItem = [[UIBarButtonItem alloc] initWithCustomView:patchBtn];
    UIBarButtonItem *copyItem = [[UIBarButtonItem alloc] initWithCustomView:copyBtn];
    
    UIBarButtonItem *spacer = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    spacer.width = 8;
    
    self.navigationItem.rightBarButtonItems = @[copyItem, spacer, patchItem, spacer, boltItem, spacer, sparkItem, spacer, eyeItem];

    // 键盘上加完成按钮
    UIToolbar *tool = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 0, 44)];
    tool.items = @[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
                   [[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(dismissKeyboard)]];
    self.searchBar.inputAccessoryView = tool;
    self.tableView.tableHeaderView = header;

    self.filteredResults = self.allResults;
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
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"Cell"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
    DHScannerResult *r = self.filteredResults[ip.row];
    if ([r.methodName isEqualToString:@"(class)"]) {
        c.textLabel.text = [NSString stringWithFormat:@"@interface %@", r.className];
    } else {
        c.textLabel.text = r.fullSignature ?: r.methodName;
    }
    c.textLabel.font = [UIFont systemFontOfSize:12];
    c.textLabel.numberOfLines = 1;
    c.textLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    c.detailTextLabel.text = [NSString stringWithFormat:@"In Class: %@", r.className];
    c.detailTextLabel.font = [UIFont systemFontOfSize:10];
    c.detailTextLabel.textColor = [UIColor grayColor];
    // 右侧多选框：选中打勾，没选中不显示
    NSString *rowKey = [NSString stringWithFormat:@"%@|%@", r.className, r.methodName];
    c.accessoryType = [_selectedSet containsObject:rowKey] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;

    // 第三行：AI 翻译结果（先查本地缓存，再查运行时缓存，缓存key只用方法名）
    if (!r.dh_translation) {
        NSString *cacheKey = r.methodName;
        r.dh_translation = [DHAIManager translationForKey:cacheKey];
    }
    UILabel *thirdLabel = [c.contentView viewWithTag:999];
    if (!thirdLabel) {
        thirdLabel = [[UILabel alloc] init];
        thirdLabel.tag = 999;
        thirdLabel.font = [UIFont systemFontOfSize:10];
        thirdLabel.textColor = [UIColor systemBlueColor];
        thirdLabel.numberOfLines = 1;
        thirdLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [c.contentView addSubview:thirdLabel];
    }
    thirdLabel.text = r.dh_translation;
    thirdLabel.hidden = (r.dh_translation.length == 0);
    thirdLabel.frame = CGRectMake(16, 44, c.contentView.bounds.size.width - 56, 14);

    // 已存在的补丁高亮绿色，并显示修改后的返回值
    NSString *key = [NSString stringWithFormat:@"%@|%@", r.className, r.methodName];
    DHHookInfo *matchedHook = nil;
    for (DHHookInfo *h in [DHHookManager sharedManager].savedHooks) {
        if ([h.className isEqualToString:r.className] && [h.selectorName isEqualToString:r.methodName]) {
            matchedHook = h;
            break;
        }
    }
    if (matchedHook) {
        c.textLabel.textColor = [UIColor systemGreenColor];
        // 根据returnType显示对应的返回值
        NSString *returnStr = @"";
        switch (matchedHook.returnType) {
            case DHHookReturnTrue: returnStr = @"TRUE"; break;
            case DHHookReturnFalse: returnStr = @"FALSE"; break;
            case DHHookReturnVoid: returnStr = @"void"; break;
            case DHHookReturnNil: returnStr = @"nil"; break;
            case DHHookReturnZero: returnStr = @"0"; break;
            case DHHookReturnCustomString:
            case DHHookReturnCustomNumber:
            case DHHookReturnCustomValue:
                if (matchedHook.customValue) {
                    returnStr = [NSString stringWithFormat:@"%@", matchedHook.customValue];
                }
                break;
            default: break;
        }
        if (returnStr.length > 0) {
            c.textLabel.text = [NSString stringWithFormat:@"%@ → %@", c.textLabel.text, returnStr];
        }
    } else {
        c.textLabel.textColor = [UIColor labelColor];
    }
    return c;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    DHScannerResult *r = self.filteredResults[ip.row];
    // 点行 = 切换选中状态（多选）
    if (!_selectedSet) _selectedSet = [NSMutableSet new];
    NSString *rowKey = [NSString stringWithFormat:@"%@|%@", r.className, r.methodName];
    if ([_selectedSet containsObject:rowKey]) {
        [_selectedSet removeObject:rowKey];
    } else {
        [_selectedSet addObject:rowKey];
    }
    [t reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
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
    [sheet addAction:[UIAlertAction actionWithTitle:@"拦截/空实现 (void)" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [self addHook:r returnType:DHHookReturnVoid custom:nil];
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
    // 从NSUserDefaults读取所有文件夹
    NSMutableSet *folderSet = [NSMutableSet setWithArray:[DHPatchListVC dhLoadFolders]];
    for (DHHookInfo *h in [DHHookManager sharedManager].savedHooks) {
        if (h.folderName.length) [folderSet addObject:h.folderName];
    }
    NSArray *folders = [[folderSet allObjects] sortedArrayUsingSelector:@selector(compare:)];

    if (folders.count == 0) {
        // 没有文件夹，直接存根目录
        [self doAddHook:r returnType:type custom:custom folder:nil];
        return;
    }

    // 有文件夹，弹出选择
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"请选择保存位置" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"根目录" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self doAddHook:r returnType:type custom:custom folder:nil];
    }]];
    for (NSString *fname in folders) {
        [sheet addAction:[UIAlertAction actionWithTitle:fname style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [self doAddHook:r returnType:type custom:custom folder:fname];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)doAddHook:(DHScannerResult *)r returnType:(DHHookReturnType)type custom:(NSString *)custom folder:(NSString *)folder {
    // 清理方法名：扫描器里(class)是标记，不是方法名
    BOOL isClassEntry = [r.methodName hasPrefix:@"(class)"];
    NSString *selName = r.methodName;
    if (isClassEntry) selName = @"class";

    // 去重：同文件夹下同类同方法不重复添加
    for (DHHookInfo *existing in [DHHookManager sharedManager].savedHooks) {
        if ([existing.className isEqualToString:r.className] &&
            [existing.selectorName isEqualToString:selName] &&
            ((!existing.folderName.length && !folder.length) || [existing.folderName isEqualToString:folder ?: @""])) {
            [self showToast:@"该补丁已存在"];
            return;
        }
    }

    DHHookInfo *h = [DHHookInfo new];
    h.className = r.className;
    h.selectorName = selName;
    h.isClassMethod = r.isClassMethod;
    h.returnType = type;
    h.customValue = custom;
    h.folderName = folder;
    // 源头推断真实返回类型
    NSString *sel = selName;
    NSString *realType;
    if ([sel hasPrefix:@"set"]) realType = @"void";
    else if ([sel hasPrefix:@"is"] || [sel hasPrefix:@"has"] || [sel hasPrefix:@"should"]) realType = @"BOOL";
    else if ([sel hasPrefix:@"init"]) realType = @"id";
    else realType = r.returnType ?: @"id";
    h.realReturnType = realType;
    h.argCount = [[selName componentsSeparatedByString:@":"] count] - 1;
    [[DHHookManager sharedManager] addHook:h];
    NSString *loc = folder ?: @"根目录";
    [self showToast:[NSString stringWithFormat:@"补丁已保存至 %@", loc]];
}

- (void)translateWithAI {
    DHAIConfig *cfg = [DHAIManager sharedManager].config;
    if (!cfg.apiKey.length) { [self showProgress:@"请先在 AI 配置中心填写 API Key"]; return; }
    if (!cfg.apiURL.length) { [self showProgress:@"请先在 AI 配置中心填写 API 地址"]; return; }

    NSArray *results = self.filteredResults;
    if (results.count == 0) { [self showProgress:@"当前无结果可翻译"]; return; }

    // 开启无声音频保活，让翻译在后台继续跑，不被系统挂起
    [[DHKeepAliveManager shared] startSilentLoop];

    [self showProgress:[NSString stringWithFormat:@"开始逐轮翻译，每轮1000个，共约%ld轮", (long)((results.count + 999) / 1000)]];

    // 泄压轮次：从第0个开始，每轮只取1000个切片，处理完泄压再进下一轮
    [self processSliceFrom:0 results:results retryCount:0];
}

// 处理从startIdx开始的一个切片（1000个），查缓存过滤后提交，完成后推进下一轮
- (void)processSliceFrom:(NSInteger)startIdx results:(NSArray *)results retryCount:(NSInteger)retryCount {
    NSInteger sliceSize = 1000;
    NSInteger end = MIN(startIdx + sliceSize, results.count);

    if (startIdx >= results.count) {
        [self.tableView reloadData];
        [[DHKeepAliveManager shared] stopSilent];
        [self showProgress:@"全部翻译完成！"];
        return;
    }

    [self showProgress:[NSString stringWithFormat:@"第%ld-%ld个 / 共%ld个，查缓存后提交", (long)(startIdx+1), (long)end, (long)results.count]];

    // 放后台线程对当前1000个切片查缓存过滤，不卡UI；只收集这一片，不累积
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *slice = [NSMutableArray new];
        for (NSInteger i = startIdx; i < end; i++) {
            DHScannerResult *r = results[i];
            if ([r.methodName isEqualToString:@"(class)"]) continue;
            NSString *cached = [DHAIManager translationForKey:r.methodName];
            if (cached.length > 0) {
                r.dh_translation = cached;
                continue;
            }
            [slice addObject:r];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (slice.count == 0) {
                // 这一片全是缓存，直接推进下一轮（泄压，不保留）
                [self processSliceFrom:end results:results retryCount:0];
                return;
            }
            [self sendSlice:slice rangeStart:startIdx rangeEnd:end results:results retryCount:retryCount];
        });
    });
}

// 提交当前切片给AI，返回后存缓存、刷新，再泄压推进下一轮
- (void)sendSlice:(NSArray *)slice rangeStart:(NSInteger)rangeStart rangeEnd:(NSInteger)rangeEnd results:(NSArray *)results retryCount:(NSInteger)retryCount {
    NSMutableArray *methodList = [NSMutableArray new];
    for (DHScannerResult *r in slice) {
        [methodList addObject:r.methodName];
    }

    DHAIConfig *cfg = [DHAIManager sharedManager].config;
    NSString *apiURL = cfg.apiURL;
    if (![apiURL hasSuffix:@"/chat/completions"]) {
        apiURL = [apiURL stringByAppendingString:@"/chat/completions"];
    }

    NSDictionary *body = @{
        @"model": cfg.model ?: @"deepseek-chat",
        @"messages": @[
            @{@"role": @"system", @"content": @"你是 iOS 逆向工程助手。输入是一个 Objective-C 方法名数组，你需要把每个方法名翻译成简洁的中文意思。严格返回 JSON 对象，key 是原方法名，value 是中文翻译。不要输出任何其他内容。"},
            @{@"role": @"user", @"content": [methodList componentsJoinedByString:@"\n"]},
        ],
        @"temperature": @0.3,
        @"response_format": @{@"type": @"json_object"},
    };

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:apiURL]];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", cfg.apiKey] forHTTPHeaderField:@"Authorization"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    req.timeoutInterval = 600;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSInteger maxRetry = 2;
            // 失败：重试本切片，超过2次则跳过推进下一轮（泄压，不卡住）
            void (^nextRound)(void) = ^{
                [self processSliceFrom:rangeEnd results:results retryCount:0];
            };
            void (^retryBlock)(void) = ^{
                if (retryCount < maxRetry) {
                    NSInteger newRetry = retryCount + 1;
                    [self showProgress:[NSString stringWithFormat:@"第%ld-%ld个失败，第%ld次重试", (long)(rangeStart+1), (long)rangeEnd, newRetry]];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [self sendSlice:slice rangeStart:rangeStart rangeEnd:rangeEnd results:results retryCount:newRetry];
                    });
                } else {
                    [self showProgress:[NSString stringWithFormat:@"第%ld-%ld个失败已跳过", (long)(rangeStart+1), (long)rangeEnd]];
                    nextRound();
                }
            };

            if (error) { retryBlock(); return; }
            NSError *jsonErr;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
            if (jsonErr) { retryBlock(); return; }
            NSString *content = json[@"choices"][0][@"message"][@"content"];
            if (!content.length) { retryBlock(); return; }

            NSError *parseErr;
            NSDictionary *transMap = [NSJSONSerialization JSONObjectWithData:[content dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&parseErr];
            if (parseErr || !transMap) { retryBlock(); return; }

            // 只更新当前切片对象并存缓存，不遍历全部，泄压
            for (DHScannerResult *r in slice) {
                NSString *zh = transMap[r.methodName];
                if (zh && [zh isKindOfClass:[NSString class]]) {
                    r.dh_translation = zh;
                    [DHAIManager setTranslation:zh forKey:r.methodName];
                }
            }
            [self.tableView reloadData];

            // 泄压：slice局部释放，推进下一轮
            [self processSliceFrom:rangeEnd results:results retryCount:0];
        });
    }];
    [task resume];
}

- (void)batchCopy {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"复制格式" message:@"先选复制内容，再输入区间" preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"仅方法名（适合发AI翻译）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        self->_copyFormat = 1; [self presentCopyRangeInput];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"仅类名" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        self->_copyFormat = 2; [self presentCopyRangeInput];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"类名 + 方法名（原格式）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        self->_copyFormat = 0; [self presentCopyRangeInput];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)presentCopyRangeInput {
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
        if (_copyFormat == 1) {
            [lines addObject:r.methodName ?: @""];
        } else if (_copyFormat == 2) {
            [lines addObject:r.className ?: @""];
        } else {
            [lines addObject:[NSString stringWithFormat:@"-%@ In Class: %@", r.methodName, r.className]];
        }
    }
    [UIPasteboard generalPasteboard].string = [lines componentsJoinedByString:@"\n"];
    [self showToast:[NSString stringWithFormat:@"已复制第%ld-%ld条", (long)(start+1), (long)end]];
}

- (void)filterBtnTapped:(UIButton *)btn {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"筛选" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *titles = @[
        _searchScope == 0 ? @"✓ 全部" : @"  全部",
        _searchScope == 1 ? @"✓ 仅类名" : @"  仅类名",
        _searchScope == 2 ? @"✓ 仅方法名" : @"  仅方法名",
        @"",
        _filterSystemClasses ? @"✓ 过滤系统类" : @"  过滤系统类",
        _filterBOOLOnly ? @"✓ 仅看BOOL方法" : @"  仅看BOOL方法",
        _filterVoidOnly ? @"✓ 仅看void方法" : @"  仅看void方法",
        _filterHasArgs ? @"✓ 仅看带参方法" : @"  仅看带参方法",
        _filterSetPrefix ? @"✓ 过滤set开头" : @"  过滤set开头",
    ];
    for (NSInteger i = 0; i < titles.count; i++) {
        if (i == 3) { [sheet addAction:[UIAlertAction actionWithTitle:@"———" style:UIAlertActionStyleDestructive handler:nil]]; continue; }
        [sheet addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            if (i < 3) self->_searchScope = i;
            else if (i == 4) self->_filterSystemClasses = !self->_filterSystemClasses;
            else if (i == 5) self->_filterBOOLOnly = !self->_filterBOOLOnly;
            else if (i == 6) self->_filterVoidOnly = !self->_filterVoidOnly;
            else if (i == 7) self->_filterHasArgs = !self->_filterHasArgs;
            else if (i == 8) self->_filterSetPrefix = !self->_filterSetPrefix;
            [self filterBtnTapped:btn]; // 刷新菜单
            [self applyFilter];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)setupDefaultKeywordFolders {
    NSArray *existing = [[NSUserDefaults standardUserDefaults] arrayForKey:@"DHKeywordFolders"] ?: @[];
    NSMutableArray *existingNames = [NSMutableArray new];
    for (NSDictionary *f in existing) [existingNames addObject:f[@"name"]];

    NSMutableArray *toAdd = [NSMutableArray new];

    // 正则词库 4 个
    if (![existingNames containsObject:@"[正则]定时器 / 计时器 / 轮询"]) {
        [toAdd addObject:@{
            @"name": @"[正则]定时器 / 计时器 / 轮询",
            @"content": @"(?i).*(is|has|check|should|can|need|verify|validate|allow|enable|disable|require|grant|revoke|get|set|show|hide|remove|block|unlock|access|use|fetch|load|request|create|update|delete|query|report|detect|filter|monitor|track|start|stop|try|pay|buy|purchase|subscribe|renew|upgrade|refund|cancel|schedule|delay|clear|fire|invalidate|tick|trigger|timeout|poll|loop|wait|sleep|reset|restart|pause|resume|count).*(timer|countdown|interval|delay|timeout|tick|polling|heartbeat|schedule|task|alarm|dispatch|handler|coroutine|loop|wait|sleep|duration|elapsed).*",
            @"isRegex": @YES,
        }];
    }
    if (![existingNames containsObject:@"[正则]音视频处理 / 播放 / 录制"]) {
        [toAdd addObject:@{
            @"name": @"[正则]音视频处理 / 播放 / 录制",
            @"content": @"(?i).*(is|has|check|should|can|need|verify|validate|allow|enable|disable|require|grant|revoke|get|set|show|hide|remove|block|unlock|access|use|fetch|load|request|create|update|delete|query|report|detect|filter|monitor|track|start|stop|try|pay|buy|purchase|subscribe|renew|upgrade|refund|cancel|play|pause|resume|seek|record|capture|save|render|compress|trim|crop|cut|split|merge|export|import|download|upload|stream|mute|unmute|scale|resize|rotate|dial).*(video|audio|voice|sound|music|media|player|recorder|stream|render|frame|codec|compress|trim|crop|volume|mute|speaker|microphone|mic|camera|subtitle|caption).*",
            @"isRegex": @YES,
        }];
    }
    if (![existingNames containsObject:@"[正则]通话业务 / 语音计费"]) {
        [toAdd addObject:@{
            @"name": @"[正则]通话业务 / 语音计费",
            @"content": @"(?i).*(is|has|check|should|can|need|verify|validate|allow|enable|disable|require|grant|revoke|get|set|show|hide|remove|block|unlock|access|use|fetch|load|request|create|update|delete|query|report|detect|filter|monitor|track|start|stop|try|pay|buy|purchase|subscribe|renew|upgrade|refund|cancel|end|hangup|answer|accept|reject|decline|hold|unhold|deduct|charge|consume|calculate|count|dial).*(call|dial|phone|voice|speaker|microphone|balance|coin|diamond|credit|fee|price|rate|cost|billing|charge|duration|time|minute|second|hold|mute|hangup).*",
            @"isRegex": @YES,
        }];
    }
    if (![existingNames containsObject:@"[正则]送礼 / 打赏 / 虚拟礼物"]) {
        [toAdd addObject:@{
            @"name": @"[正则]送礼 / 打赏 / 虚拟礼物",
            @"content": @"(?i).*(is|has|check|should|can|need|verify|validate|allow|enable|disable|require|grant|revoke|get|set|show|hide|remove|block|unlock|access|use|fetch|load|request|create|update|delete|query|report|detect|filter|monitor|track|start|stop|try|pay|buy|purchase|subscribe|renew|upgrade|refund|cancel|select|send|give|receive|play|calculate|deduct|charge|consume|animate).*(gift|present|tip|reward|combo|animation|effect|panel|sender|receiver|balance|coin|diamond|price|cost|count|list).*",
            @"isRegex": @YES,
        }];
    }

    // 普通词库 4 个
    if (![existingNames containsObject:@"[词库]定时器/计时器/轮询/心跳/调度"]) {
        [toAdd addObject:@{
            @"name": @"[词库]定时器/计时器/轮询/心跳/调度",
            @"content": @"Timer，NSTimer，CADisplayLink，DispatchSourceTimer，CountDownTimer，Handler，TimerTask，ScheduledExecutorService，AlarmManager，RxTimer，TimerManager，TimerUtil，TimerHelper，HeartbeatManager，PollingManager，TimerTaskManager，CountDownUtil，isTimerRunning，isTimerActive，isTimerValid，isCountdownRunning，isTimeout，hasTimeout，checkTimeout，isTimeUp，getTimer，getTimerState，getInterval，getDelay，getPeriod，getTick，getElapsedTime，getRemainingTime，getCallDuration，getStartTime，getEndTime，startTimer，stopTimer，pauseTimer，resumeTimer，cancelTimer，resetTimer，restartTimer，invalidateTimer，scheduleTimer，scheduleDelay，scheduleTask，scheduleAtFixedRate，startCountdown，stopCountdown，cancelCountdown，startPolling，stopPolling，startHeartbeat，stopHeartbeat，postDelayed，removeCallbacks，asyncAfter，onTick，onFinish，onTimerTick，onCountdownTick，tick，fire，invalidate，schedule，unschedule，clearTimeout，setTimeout，setInterval，clearInterval",
            @"isRegex": @NO,
        }];
    }
    if (![existingNames containsObject:@"[词库]音视频处理/播放/录制/剪辑/压缩"]) {
        [toAdd addObject:@{
            @"name": @"[词库]音视频处理/播放/录制/剪辑/压缩",
            @"content": @"VideoPlayer，VideoView，VideoEditor，VideoCompressor，AudioPlayer，AudioRecorder，AudioManager，MediaPlayer，MediaRecorder，VideoRenderer，VideoEncoder，VideoDecoder，isVideo，hasVideo，isVideoValid，isVideoPlaying，isVideoPaused，isVideoStopped，isVideoEnded，isVideoLoading，isVideoBuffering，isVideoCompressed，isVideoMuted，isAudio，hasAudio，isAudioPlaying，isAudioPaused，isAudioMuted，isRecording，isMicrophoneOn，isSpeakerOn，getVideo，getVideoInfo，getVideoFormat，getVideoSize，getVideoResolution，getVideoBitrate，getVideoFrameRate，getAudio，getAudioInfo，getAudioDuration，getAudioFormat，getAudioVolume，getMedia，loadVideo，playVideo，pauseVideo，stopVideo，resumeVideo，seekVideo，restartVideo，downloadVideo，uploadVideo，exportVideo，importVideo，compressVideo，trimVideo，cropVideo，cutVideo，splitVideo，mergeVideo，rotateVideo，resizeVideo，scaleVideo，renderVideo，previewVideo，recordVideo，captureVideo，saveVideo，deleteVideo，shareVideo，playAudio，pauseAudio，stopAudio，resumeAudio，seekAudio，recordAudio，startRecord，stopRecord，setVideoQuality，setVideoSpeed，setVideoVolume，setVideoMute，setVideoResolution，setVideoBitrate，setAudioVolume，setAudioSpeed，setAudioQuality，setAudioMute，muteMicrophone，unmuteMicrophone，enableSpeaker，disableSpeaker",
            @"isRegex": @NO,
        }];
    }
    if (![existingNames containsObject:@"[词库]通话业务/语音计费/按时长扣费/拨号"]) {
        [toAdd addObject:@{
            @"name": @"[词库]通话业务/语音计费/按时长扣费/拨号",
            @"content": @"CallManager，CallKit，CallBillingManager，CallChargeManager，VoiceEngine，VoiceCallBilling，AudioCallFee，isCall，hasCall，isCalling，isCallActive，isCallConnected，isCallEnded，isCallIncoming，isCallOutgoing，isCallMuted，isCallHeld，isCallBilling，hasCallBilling，isBillingActive，isCharging，isCallCharging，isBalanceEnoughForCall，isCallBalanceSufficient，isCallBillingReached，isNeedChargeCall，isCallTimeExceeded，isCallTimeout，getCallRate，getCallPrice，getCallPricePerMinute，getCallFee，getVoiceCallFee，getCallCost，getCallMinutePrice，getCallBalance，getCallDuration，getCallBillingDuration，getCallingTime，getRemainingCallTime，getCallStatus，getCallHistory，getCallerInfo，startCall，endCall，hangUp，answerCall，acceptCall，rejectCall，declineCall，muteCall，unmuteCall，holdCall，unholdCall，startCallTimer，startCallBilling，startCallCharging，stopCallTimer，stopCallBilling，stopCallCharging，pauseCallBilling，resumeCallBilling，calculateCallCost，calculateCallFee，calculateCallDuration，deductCallFee，deductCallCoin，deductCallDiamond，chargeCallFee，chargeCallCoin，chargeCallDiamond，consumeCallCoin，consumeCallDiamond，payForCall，payCallFee，checkCallTimeLimit，checkCallBalanceLimit，checkCallCostLimit",
            @"isRegex": @NO,
        }];
    }
    if (![existingNames containsObject:@"[词库]送礼/打赏/虚拟礼物/连击特效"]) {
        [toAdd addObject:@{
            @"name": @"[词库]送礼/打赏/虚拟礼物/连击特效",
            @"content": @"GiftManager，GiftController，GiftPanel，GiftAnimator，GiftSender，GiftReceiver，GiftComboUtils，VirtualGift，LiveGift，SendGiftUtils，isGift，hasGift，isGiftAvailable，isGiftSelected，isGiftSent，isGiftSending，isGiftCombo，isComboActive，isComboTimeout，isEnoughBalanceForGift，isGiftAnimationPlaying，getGift，getGiftList，getGiftInfo，getGiftId，getGiftName，getGiftIcon，getGiftPrice，getGiftCost，getGiftCount，getGiftComboCount，getGiftSender，getGiftReceiver，getGiftHistory，getGiftBalance，getGiftAnimation，getGiftEffect，setGift，setGiftCount，setGiftComboCount，setGiftPrice，selectGift，sendGift，giveGift，sendVirtualGift，sendComboGift，sendGiftToUser，receiveGift，buyGift，purchaseGift，loadGiftList，loadGiftPanel，showGiftPanel，hideGiftPanel，showGiftAnimation，playGiftAnimation，showGiftEffect，playGiftEffect，hideGiftAnimation，clearGiftAnimation，startCombo，stopCombo，resetCombo，calculateGiftTotal，calculateGiftCost，calculateGiftPrice，deductGiftCoin，deductGiftDiamond，chargeGiftFee，consumeGiftCoin，payForGift，trackGiftSend，reportGiftSend",
            @"isRegex": @NO,
        }];
    }

    if (toAdd.count > 0) {
        NSMutableArray *newArr = [NSMutableArray arrayWithArray:existing];
        [newArr addObjectsFromArray:toAdd];
        [[NSUserDefaults standardUserDefaults] setObject:newArr forKey:@"DHKeywordFolders"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (void)openKeywordMenu {
    NSArray *folders = [[NSUserDefaults standardUserDefaults] arrayForKey:@"DHKeywordFolders"];
    if (folders.count == 0) { [self showToast:@"请先在主界面创建词库"]; return; }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"选择词库" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *f in folders) {
        [sheet addAction:[UIAlertAction actionWithTitle:f[@"name"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [self applyKeywordFolder:f];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (BOOL)passFunnelFilter:(DHScannerResult *)r {
    // 选了仅看BOOL或仅看void的时候，过滤掉@interface类声明行
    if (_filterBOOLOnly || _filterVoidOnly) {
        if ([r.methodName isEqualToString:@"(class)"]) return NO;
    }
    if (_filterSystemClasses) {
        NSString *cn = r.className;
        if ([cn hasPrefix:@"NS"] || [cn hasPrefix:@"UI"] || [cn hasPrefix:@"CF"] ||
            [cn hasPrefix:@"_"] || [cn hasPrefix:@"__"] || [cn hasPrefix:@"CA"]) return NO;
    }
    if (_filterBOOLOnly) {
        if (![r.returnType caseInsensitiveCompare:@"bool"] == NSOrderedSame) return NO;
    }
    if (_filterVoidOnly) {
        if (![r.returnType caseInsensitiveCompare:@"void"] == NSOrderedSame) return NO;
    }
    if (_filterHasArgs) {
        if (![r.methodName containsString:@":"]) return NO;
    }
    if (_filterSetPrefix) {
        // 过滤掉 set 开头的方法
        NSString *lower = r.methodName.lowercaseString;
        if ([lower hasPrefix:@"set"]) return NO;
    }
    return YES;
}

- (void)applyKeywordFolder:(NSDictionary *)folder {
    NSString *content = folder[@"content"] ?: @"";
    BOOL isRegex = [folder[@"isRegex"] boolValue];
    if (isRegex) {
        // 正则模式：每行一条正则
        NSMutableArray *regexes = [NSMutableArray new];
        NSInteger failed = 0;
        NSArray *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        for (NSString *line in lines) {
            NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (!t.length) continue;
            NSError *err = nil;
            NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:t options:NSRegularExpressionCaseInsensitive error:&err];
            if (re) [regexes addObject:re];
            else failed++;
        }
        if (regexes.count == 0) { [self showToast:@"词库为空或正则格式错误"]; return; }
        _activeRegexes = regexes;
        _activeKeywords = nil;
        if (failed > 0) [self showToast:[NSString stringWithFormat:@"%lu条成功,%ld条失败", (unsigned long)regexes.count, (long)failed]];
    } else {
        NSArray *parts = [content componentsSeparatedByCharactersInSet:
            [NSCharacterSet characterSetWithCharactersInString:@",，、/\\ \n\t"]];
        NSMutableSet *kws = [NSMutableSet new];
        for (NSString *p in parts) {
            NSString *t = [p stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (t.length) [kws addObject:t];
        }
        if (kws.count == 0) { [self showToast:@"词库为空"]; return; }
        _activeKeywords = [kws copy];
        _activeRegexes = nil;
    }
    [self searchBar:self.searchBar textDidChange:self.searchBar.text ?: @""];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self showToast:[NSString stringWithFormat:@"%@: 匹配到%lu条", folder[@"name"], (unsigned long)self.filteredResults.count]];
    });
}

- (void)applyFilter {
    [self searchBar:self.searchBar textDidChange:self.searchBar.text];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [_searchDebounce invalidate];
    NSString *kw = [searchText lowercaseString];
    NSInteger scope = _searchScope;
    BOOL fSys = _filterSystemClasses;
    BOOL fBool = _filterBOOLOnly;
    BOOL fArgs = _filterHasArgs;
    NSArray *all = self.allResults;
    NSSet *activeKws = _activeKeywords;
    NSArray *activeRegexes = _activeRegexes;
    _searchDebounce = [NSTimer scheduledTimerWithTimeInterval:0.3 repeats:NO block:^(NSTimer *t) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            // 一次性读整个翻译缓存，避免逐个方法读plist导致慢
            NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            NSString *cachePath = [dir stringByAppendingPathComponent:@"iOSDebugHelper/translations.plist"];
            NSDictionary *transCache = [NSDictionary dictionaryWithContentsOfFile:cachePath] ?: @{};

            NSMutableArray *result = [NSMutableArray new];
            for (DHScannerResult *r in all) {
                // 先跑快速漏斗过滤（最快的先跑，快速淘汰大部分）
                if (![self passFunnelFilter:r]) continue;
                // 搜索框关键词（类名/方法名/翻译名）
                if (kw.length) {
                    // 直接从缓存字典查，不逐个读文件
                    NSString *cacheKey = [NSString stringWithFormat:@"%@|%@", r.className, r.methodName];
                    NSString *trans = transCache[cacheKey] ?: @"";
                    BOOL matchClass = [r.className.lowercaseString containsString:kw];
                    BOOL matchMethod = [r.methodName.lowercaseString containsString:kw];
                    BOOL matchTrans = [trans containsString:searchText];
                    if (!matchClass && !matchMethod && !matchTrans) continue;
                }
                [result addObject:r];
            }
            // 闪电词库过滤（放在最后，因为正则慢，只对已经过了快速过滤的结果跑）
            if (activeKws.count || activeRegexes.count) {
                NSMutableArray *afterKw = [NSMutableArray new];
                for (DHScannerResult *r in result) {
                    BOOL hit = NO;
                    for (NSString *akw in activeKws) {
                        if ([r.className rangeOfString:akw options:NSCaseInsensitiveSearch].location != NSNotFound ||
                            [r.methodName rangeOfString:akw options:NSCaseInsensitiveSearch].location != NSNotFound) { hit = YES; break; }
                    }
                    if (hit) { [afterKw addObject:r]; continue; }
                    for (NSRegularExpression *re in activeRegexes) {
                        if ([re rangeOfFirstMatchInString:r.methodName options:0 range:NSMakeRange(0, r.methodName.length)].location != NSNotFound ||
                            [re rangeOfFirstMatchInString:r.className options:0 range:NSMakeRange(0, r.className.length)].location != NSNotFound) { hit = YES; break; }
                    }
                    if (hit) [afterKw addObject:r];
                }
                result = afterKw;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                self.filteredResults = result;
                [self.tableView reloadData];
            });
        });
    }];
}

- (void)dismissKeyboard {
    [self.searchBar resignFirstResponder];
}

- (void)showToast:(NSString *)msg {
    // 先关闭之前的弹窗
    if (self.presentedViewController) {
        [self.presentedViewController dismissViewControllerAnimated:YES completion:^{
            [self presentNewToast:msg];
        }];
    } else {
        [self presentNewToast:msg];
    }
}

- (void)presentNewToast:(NSString *)msg {
    UIAlertController *t = [UIAlertController alertControllerWithTitle:@"提示" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [t addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:t animated:YES completion:nil];
}

// 自动消失的轻量进度条，不弹窗、不需要点确定，重复调用只更新文字
- (void)showProgress:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            UIView *container = self.view;
            if (!container) return;
            // 先移除上一条临时提示条（tag 标记），不用成员变量，避免残留
            for (UIView *v in container.subviews) {
                if (v.tag == 99877) [v removeFromSuperview];
            }
            UILabel *label = [[UILabel alloc] init];
            label.tag = 99877;
            label.font = [UIFont systemFontOfSize:13];
            label.textColor = [UIColor whiteColor];
            label.textAlignment = NSTextAlignmentCenter;
            label.numberOfLines = 0;
            label.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
            label.layer.cornerRadius = 10;
            label.layer.masksToBounds = YES;
            label.text = msg;
            CGFloat w = MIN(300, container.bounds.size.width - 40);
            if (w < 120) w = 120;
            CGSize fit = [label sizeThatFits:CGSizeMake(w, CGFLOAT_MAX)];
            label.frame = CGRectMake((container.bounds.size.width - w)/2, CGRectGetMidY(container.bounds) - 30, w, fit.height + 20);
            label.alpha = 0;
            [container addSubview:label];
            [UIView animateWithDuration:0.2 animations:^{ label.alpha = 1; }];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [UIView animateWithDuration:0.3 animations:^{ label.alpha = 0; } completion:^(BOOL finished) {
                    [label removeFromSuperview];
                }];
            });
        } @catch (NSException *e) {}
    });
}

- (void)startMonitorFromScan {
    NSArray *results = self.filteredResults;
    if (results.count == 0) { [self showToast:@"当前无筛选结果"]; return; }
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"开启方法监控" message:[NSString stringWithFormat:@"确定要监控当前列表的%lu个方法吗？\n监控后会实时打印方法调用日志。", (unsigned long)results.count] preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"确定开启" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [[DHMonitorManager shared] stop];
        [[DHMonitorManager shared] startWithResults:results];
        [self showToast:[NSString stringWithFormat:@"已监控%lu个方法", (unsigned long)results.count]];
        [self dismissViewControllerAnimated:YES completion:nil];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)batchPatchMenu {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"批量生成补丁" message:[NSString stringWithFormat:@"当前列表%lu条", (unsigned long)self.filteredResults.count] preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"返回 TRUE (YES)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self chooseFolderThenBatch: DHHookReturnTrue];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"返回 FALSE (NO)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self chooseFolderThenBatch: DHHookReturnFalse];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"返回 nil" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self chooseFolderThenBatch: DHHookReturnNil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"拦截 / 空实现 (void)" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [self chooseFolderThenBatch: DHHookReturnVoid];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"返回 0" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self chooseFolderThenBatch: DHHookReturnZero];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"自定义字符串" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self showCustomStringInput];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"自定义数字" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self showCustomNumberInput];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)showCustomStringInput {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"自定义字符串" message:@"输入要返回的字符串内容" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.placeholder = @"如 success";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"下一步" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        NSString *text = alert.textFields[0].text ?: @"";
        // 存到全局，批量补丁的时候用
        [[NSUserDefaults standardUserDefaults] setObject:text forKey:@"DH_LastCustomString"];
        [self chooseFolderThenBatch: DHHookReturnCustomString];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showCustomNumberInput {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"自定义数字" message:@"输入要返回的数字" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.placeholder = @"如 100";
        f.keyboardType = UIKeyboardTypeNumberPad;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"下一步" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        NSString *text = alert.textFields[0].text ?: @"0";
        [[NSUserDefaults standardUserDefaults] setObject:text forKey:@"DH_LastCustomNumber"];
        [self chooseFolderThenBatch: DHHookReturnCustomNumber];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)chooseFolderThenBatch:(DHHookReturnType)type {
    // 如果有选中的方法，直接对选中的批量补丁，不弹数量输入框
    if (_selectedSet.count > 0) {
        NSMutableArray *selectedResults = [NSMutableArray new];
        for (DHScannerResult *r in self.filteredResults) {
            NSString *rowKey = [NSString stringWithFormat:@"%@|%@", r.className, r.methodName];
            if ([_selectedSet containsObject:rowKey]) [selectedResults addObject:r];
        }
        [self presentFolderSheetForBatch:type limit:0 results:selectedResults];
        return;
    }
    // 没选中的，按原来逻辑：先问数量
    UIAlertController *countAlert = [UIAlertController alertControllerWithTitle:@"批量补丁数量" message:[NSString stringWithFormat:@"当前共%lu条\n输入要HOOK前多少条？(留空=全部)", (unsigned long)self.filteredResults.count] preferredStyle:UIAlertControllerStyleAlert];
    [countAlert addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = @"如 20"; f.keyboardType = UIKeyboardTypeNumberPad; }];
    [countAlert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [countAlert addAction:[UIAlertAction actionWithTitle:@"下一步" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        NSInteger limit = 0;
        NSString *txt = countAlert.textFields[0].text;
        if (txt.length) limit = txt.integerValue;
        [self presentFolderSheetForBatch:type limit:limit results:nil];
    }]];
    [self presentViewController:countAlert animated:YES completion:nil];
}

- (void)presentFolderSheetForBatch:(DHHookReturnType)type limit:(NSInteger)limit results:(NSArray *)results {
    UIAlertController *folderSheet = [UIAlertController alertControllerWithTitle:@"请选择保存位置" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [folderSheet addAction:[UIAlertAction actionWithTitle:@"根目录" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self batchPatchWithType:type folder:nil limit:limit results:results];
    }]];
    NSArray *folders = [DHPatchListVC dhLoadFolders];
    for (NSString *f in folders) {
        [folderSheet addAction:[UIAlertAction actionWithTitle:f style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [self batchPatchWithType:type folder:f limit:limit results:results];
        }]];
    }
    [folderSheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:folderSheet animated:YES completion:nil];
}

- (void)batchPatchWithType:(DHHookReturnType)type folder:(NSString *)folderName limit:(NSInteger)limit results:(NSArray *)results {
    NSArray *source = results ?: self.filteredResults;
    NSInteger added = 0;
    NSMutableArray *toRemove = [NSMutableArray new];
    NSInteger processed = 0;
    for (DHScannerResult *r in source) {
        if (limit > 0 && processed >= limit) break;
        if ([r.methodName isEqualToString:@"(class)"]) continue;
        processed++;
        for (DHHookInfo *h in [DHHookManager sharedManager].savedHooks) {
            if ([h.className isEqualToString:r.className] && [h.selectorName isEqualToString:r.methodName]) {
                [toRemove addObject:h];
                break;
            }
        }
    }
    for (DHHookInfo *h in toRemove) [[DHHookManager sharedManager] removeHook:h];
    NSMutableArray *newHooks = [NSMutableArray new];
    NSInteger addedCount = 0;
    for (DHScannerResult *r in source) {
        if (limit > 0 && addedCount >= limit) break;
        if ([r.methodName isEqualToString:@"(class)"]) continue;
        // 跳过系统类，防止hook系统方法闪退
        NSString *cn = r.className;
        if ([cn hasPrefix:@"NS"] || [cn hasPrefix:@"UI"] || [cn hasPrefix:@"CF"] ||
            [cn hasPrefix:@"_"] || [cn hasPrefix:@"__"] || [cn hasPrefix:@"CA"]) continue;
        DHHookInfo *h = [DHHookInfo new];
        h.className = r.className;
        h.selectorName = r.methodName;
        h.isClassMethod = r.isClassMethod;
        h.returnType = type;
        h.folderName = folderName;
        h.enabled = YES;
        NSString *sel = r.methodName;
        NSString *realType;
        if ([sel hasPrefix:@"set"]) realType = @"void";
        else if ([sel hasPrefix:@"is"] || [sel hasPrefix:@"has"] || [sel hasPrefix:@"should"]) realType = @"BOOL";
        else if ([sel hasPrefix:@"init"]) realType = @"id";
        else realType = r.returnType ?: @"id";
        h.realReturnType = realType;
        h.argCount = [[sel componentsSeparatedByString:@":"] count] - 1;
        [newHooks addObject:h];
        added++;
        addedCount++;
    }
    // 批量添加：直接操作数组，避免逐个save
    NSMutableArray *arr = [[DHHookManager sharedManager].savedHooks mutableCopy];
    [arr addObjectsFromArray:newHooks];
    [DHHookManager sharedManager].savedHooks = arr;
    [[DHHookManager sharedManager] saveHooks];
    // 保存文件夹开关状态为ON
    if (folderName.length > 0) {
        NSMutableDictionary *folderStates = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"DHFolderSwitchStates"] mutableCopy] ?: [NSMutableDictionary new];
        folderStates[folderName] = @(YES);
        [[NSUserDefaults standardUserDefaults] setObject:folderStates forKey:@"DHFolderSwitchStates"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    // 立即应用新hook
    for (DHHookInfo *h in newHooks) [[DHHookManager sharedManager] applyHook:h];
    [self showToast:[NSString stringWithFormat:@"批量处理%lu个补丁", (long)added]];
    // 批量补丁完成后，清空所有勾选
    [_selectedSet removeAllObjects];
    [self.tableView reloadData];
}

#pragma mark - 按钮按压动画
- (void)btnTouchDown:(UIButton *)b {
    [UIView animateWithDuration:0.15 animations:^{
        b.backgroundColor = [b.backgroundColor colorWithAlphaComponent:0.7];
    }];
}

- (void)btnTouchUp:(UIButton *)b {
    [UIView animateWithDuration:0.25 animations:^{
        b.backgroundColor = [b.backgroundColor colorWithAlphaComponent:1.0];
    }];
}

@end

#pragma mark - 主菜单
@interface DHMainMenuViewController ()
@property (nonatomic, copy) NSArray *menuSections;
@end

@interface DHMonitorListVC : UITableViewController
@property (nonatomic, copy) void(^didSelectEvent)(DHMonitorEvent *e);
@end

@implementation DHMainMenuViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"iOS调试助手";
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
    [self setupDefaultKeywordFolders];
    [self buildMenu];
}

- (void)setupDefaultKeywordFolders {
    NSArray *existing = [[NSUserDefaults standardUserDefaults] arrayForKey:@"DHKeywordFolders"] ?: @[];
    NSMutableArray *existingNames = [NSMutableArray new];
    for (NSDictionary *f in existing) [existingNames addObject:f[@"name"]];

    NSMutableArray *toAdd = [NSMutableArray new];

    // 正则词库 4 个
    if (![existingNames containsObject:@"[正则]定时器 / 计时器 / 轮询"]) {
        [toAdd addObject:@{
            @"name": @"[正则]定时器 / 计时器 / 轮询",
            @"content": @"(?i).*(is|has|check|should|can|need|verify|validate|allow|enable|disable|require|grant|revoke|get|set|show|hide|remove|block|unlock|access|use|fetch|load|request|create|update|delete|query|report|detect|filter|monitor|track|start|stop|try|pay|buy|purchase|subscribe|renew|upgrade|refund|cancel|schedule|delay|clear|fire|invalidate|tick|trigger|timeout|poll|loop|wait|sleep|reset|restart|pause|resume|count).*(timer|countdown|interval|delay|timeout|tick|polling|heartbeat|schedule|task|alarm|dispatch|handler|coroutine|loop|wait|sleep|duration|elapsed).*",
            @"isRegex": @YES,
        }];
    }
    if (![existingNames containsObject:@"[正则]音视频处理 / 播放 / 录制"]) {
        [toAdd addObject:@{
            @"name": @"[正则]音视频处理 / 播放 / 录制",
            @"content": @"(?i).*(is|has|check|should|can|need|verify|validate|allow|enable|disable|require|grant|revoke|get|set|show|hide|remove|block|unlock|access|use|fetch|load|request|create|update|delete|query|report|detect|filter|monitor|track|start|stop|try|pay|buy|purchase|subscribe|renew|upgrade|refund|cancel|play|pause|resume|seek|record|capture|save|render|compress|trim|crop|cut|split|merge|export|import|download|upload|stream|mute|unmute|scale|resize|rotate|dial).*(video|audio|voice|sound|music|media|player|recorder|stream|render|frame|codec|compress|trim|crop|volume|mute|speaker|microphone|mic|camera|subtitle|caption).*",
            @"isRegex": @YES,
        }];
    }
    if (![existingNames containsObject:@"[正则]通话业务 / 语音计费"]) {
        [toAdd addObject:@{
            @"name": @"[正则]通话业务 / 语音计费",
            @"content": @"(?i).*(is|has|check|should|can|need|verify|validate|allow|enable|disable|require|grant|revoke|get|set|show|hide|remove|block|unlock|access|use|fetch|load|request|create|update|delete|query|report|detect|filter|monitor|track|start|stop|try|pay|buy|purchase|subscribe|renew|upgrade|refund|cancel|end|hangup|answer|accept|reject|decline|hold|unhold|deduct|charge|consume|calculate|count|dial).*(call|dial|phone|voice|speaker|microphone|balance|coin|diamond|credit|fee|price|rate|cost|billing|charge|duration|time|minute|second|hold|mute|hangup).*",
            @"isRegex": @YES,
        }];
    }
    if (![existingNames containsObject:@"[正则]送礼 / 打赏 / 虚拟礼物"]) {
        [toAdd addObject:@{
            @"name": @"[正则]送礼 / 打赏 / 虚拟礼物",
            @"content": @"(?i).*(is|has|check|should|can|need|verify|validate|allow|enable|disable|require|grant|revoke|get|set|show|hide|remove|block|unlock|access|use|fetch|load|request|create|update|delete|query|report|detect|filter|monitor|track|start|stop|try|pay|buy|purchase|subscribe|renew|upgrade|refund|cancel|select|send|give|receive|play|calculate|deduct|charge|consume|animate).*(gift|present|tip|reward|combo|animation|effect|panel|sender|receiver|balance|coin|diamond|price|cost|count|list).*",
            @"isRegex": @YES,
        }];
    }

    // 普通词库 4 个
    if (![existingNames containsObject:@"[词库]定时器/计时器/轮询/心跳/调度"]) {
        [toAdd addObject:@{
            @"name": @"[词库]定时器/计时器/轮询/心跳/调度",
            @"content": @"Timer，NSTimer，CADisplayLink，DispatchSourceTimer，CountDownTimer，Handler，TimerTask，ScheduledExecutorService，AlarmManager，RxTimer，TimerManager，TimerUtil，TimerHelper，HeartbeatManager，PollingManager，TimerTaskManager，CountDownUtil，isTimerRunning，isTimerActive，isTimerValid，isCountdownRunning，isTimeout，hasTimeout，checkTimeout，isTimeUp，getTimer，getTimerState，getInterval，getDelay，getPeriod，getTick，getElapsedTime，getRemainingTime，getCallDuration，getStartTime，getEndTime，startTimer，stopTimer，pauseTimer，resumeTimer，cancelTimer，resetTimer，restartTimer，invalidateTimer，scheduleTimer，scheduleDelay，scheduleTask，scheduleAtFixedRate，startCountdown，stopCountdown，cancelCountdown，startPolling，stopPolling，startHeartbeat，stopHeartbeat，postDelayed，removeCallbacks，asyncAfter，onTick，onFinish，onTimerTick，onCountdownTick，tick，fire，invalidate，schedule，unschedule，clearTimeout，setTimeout，setInterval，clearInterval",
            @"isRegex": @NO,
        }];
    }
    if (![existingNames containsObject:@"[词库]音视频处理/播放/录制/剪辑/压缩"]) {
        [toAdd addObject:@{
            @"name": @"[词库]音视频处理/播放/录制/剪辑/压缩",
            @"content": @"VideoPlayer，VideoView，VideoEditor，VideoCompressor，AudioPlayer，AudioRecorder，AudioManager，MediaPlayer，MediaRecorder，VideoRenderer，VideoEncoder，VideoDecoder，isVideo，hasVideo，isVideoValid，isVideoPlaying，isVideoPaused，isVideoStopped，isVideoEnded，isVideoLoading，isVideoBuffering，isVideoCompressed，isVideoMuted，isAudio，hasAudio，isAudioPlaying，isAudioPaused，isAudioMuted，isRecording，isMicrophoneOn，isSpeakerOn，getVideo，getVideoInfo，getVideoFormat，getVideoSize，getVideoResolution，getVideoBitrate，getVideoFrameRate，getAudio，getAudioInfo，getAudioDuration，getAudioFormat，getAudioVolume，getMedia，loadVideo，playVideo，pauseVideo，stopVideo，resumeVideo，seekVideo，restartVideo，downloadVideo，uploadVideo，exportVideo，importVideo，compressVideo，trimVideo，cropVideo，cutVideo，splitVideo，mergeVideo，rotateVideo，resizeVideo，scaleVideo，renderVideo，previewVideo，recordVideo，captureVideo，saveVideo，deleteVideo，shareVideo，playAudio，pauseAudio，stopAudio，resumeAudio，seekAudio，recordAudio，startRecord，stopRecord，setVideoQuality，setVideoSpeed，setVideoVolume，setVideoMute，setVideoResolution，setVideoBitrate，setAudioVolume，setAudioSpeed，setAudioQuality，setAudioMute，muteMicrophone，unmuteMicrophone，enableSpeaker，disableSpeaker",
            @"isRegex": @NO,
        }];
    }
    if (![existingNames containsObject:@"[词库]通话业务/语音计费/按时长扣费/拨号"]) {
        [toAdd addObject:@{
            @"name": @"[词库]通话业务/语音计费/按时长扣费/拨号",
            @"content": @"CallManager，CallKit，CallBillingManager，CallChargeManager，VoiceEngine，VoiceCallBilling，AudioCallFee，isCall，hasCall，isCalling，isCallActive，isCallConnected，isCallEnded，isCallIncoming，isCallOutgoing，isCallMuted，isCallHeld，isCallBilling，hasCallBilling，isBillingActive，isCharging，isCallCharging，isBalanceEnoughForCall，isCallBalanceSufficient，isCallBillingReached，isNeedChargeCall，isCallTimeExceeded，isCallTimeout，getCallRate，getCallPrice，getCallPricePerMinute，getCallFee，getVoiceCallFee，getCallCost，getCallMinutePrice，getCallBalance，getCallDuration，getCallBillingDuration，getCallingTime，getRemainingCallTime，getCallStatus，getCallHistory，getCallerInfo，startCall，endCall，hangUp，answerCall，acceptCall，rejectCall，declineCall，muteCall，unmuteCall，holdCall，unholdCall，startCallTimer，startCallBilling，startCallCharging，stopCallTimer，stopCallBilling，stopCallCharging，pauseCallBilling，resumeCallBilling，calculateCallCost，calculateCallFee，calculateCallDuration，deductCallFee，deductCallCoin，deductCallDiamond，chargeCallFee，chargeCallCoin，chargeCallDiamond，consumeCallCoin，consumeCallDiamond，payForCall，payCallFee，checkCallTimeLimit，checkCallBalanceLimit，checkCallCostLimit",
            @"isRegex": @NO,
        }];
    }
    if (![existingNames containsObject:@"[词库]送礼/打赏/虚拟礼物/连击特效"]) {
        [toAdd addObject:@{
            @"name": @"[词库]送礼/打赏/虚拟礼物/连击特效",
            @"content": @"GiftManager，GiftController，GiftPanel，GiftAnimator，GiftSender，GiftReceiver，GiftComboUtils，VirtualGift，LiveGift，SendGiftUtils，isGift，hasGift，isGiftAvailable，isGiftSelected，isGiftSent，isGiftSending，isGiftCombo，isComboActive，isComboTimeout，isEnoughBalanceForGift，isGiftAnimationPlaying，getGift，getGiftList，getGiftInfo，getGiftId，getGiftName，getGiftIcon，getGiftPrice，getGiftCost，getGiftCount，getGiftComboCount，getGiftSender，getGiftReceiver，getGiftHistory，getGiftBalance，getGiftAnimation，getGiftEffect，setGift，setGiftCount，setGiftComboCount，setGiftPrice，selectGift，sendGift，giveGift，sendVirtualGift，sendComboGift，sendGiftToUser，receiveGift，buyGift，purchaseGift，loadGiftList，loadGiftPanel，showGiftPanel，hideGiftPanel，showGiftAnimation，playGiftAnimation，showGiftEffect，playGiftEffect，hideGiftAnimation，clearGiftAnimation，startCombo，stopCombo，resetCombo，calculateGiftTotal，calculateGiftCost，calculateGiftPrice，deductGiftCoin，deductGiftDiamond，chargeGiftFee，consumeGiftCoin，payForGift，trackGiftSend，reportGiftSend",
            @"isRegex": @NO,
        }];
    }

    if (toAdd.count > 0) {
        NSMutableArray *newArr = [NSMutableArray arrayWithArray:existing];
        [newArr addObjectsFromArray:toAdd];
        [[NSUserDefaults standardUserDefaults] setObject:newArr forKey:@"DHKeywordFolders"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (void)buildMenu {
    self.menuSections = @[
        @{
            @"title": @"高级功能",
            @"items": @[
                @{@"title": @"智能扫描助手", @"icon": @"sparkles", @"action": @"openScanner"},
                @{@"title": @"数据分析",     @"icon": @"chart.bar.fill", @"action": @"openDataMonitor"},
                @{@"title": @"补丁管理",     @"icon": @"puzzlepiece.fill", @"action": @"openPatches"},
                @{@"title": @"关键词词库",   @"icon": @"text.badge.star", @"action": @"openKeywords"},
                @{@"title": @"AI 配置中心",   @"icon": @"cpu", @"action": @"openAIConfig"},
                @{@"title": @"网络规则",     @"icon": @"network", @"action": @"openNetworkRules"},
                @{@"title": @"全局扫描",     @"icon": @"magnifyingglass.circle.fill", @"action": @"openGlobalScan"},
                @{@"title": @"日志查看",     @"icon": @"doc.text.fill", @"action": @"openLogs"},
                @{@"title": @"动态监控",     @"icon": @"waveform", @"action": @"openMonitor"},
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
        [self runSmartScan];
    } else if ([action isEqualToString:@"openDataMonitor"]) {
        [self showDataMonitor];
    } else if ([action isEqualToString:@"openPatches"]) {
        DHPatchListVC *vc = [DHPatchListVC new];
        [self.navigationController pushViewController:vc animated:YES];
    } else if ([action isEqualToString:@"openNetworkRules"]) {
        DHNetworkRuleListVC *vc = [DHNetworkRuleListVC new];
        [self.navigationController pushViewController:vc animated:YES];
    } else if ([action isEqualToString:@"openKeywords"]) {
        DHKeywordFolderVC *vc = [DHKeywordFolderVC new];
        [self.navigationController pushViewController:vc animated:YES];
    } else if ([action isEqualToString:@"openAIConfig"]) {
        DHAIConfigVC *vc = [DHAIConfigVC new];
        [self.navigationController pushViewController:vc animated:YES];
    } else if ([action isEqualToString:@"openGlobalScan"]) {
        [self runFullScan];
    } else if ([action isEqualToString:@"openLogs"]) {
        [self showLogs];
    } else if ([action isEqualToString:@"openMonitor"]) {
        [self showMonitor];
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

- (void)runSmartScan {
    [self openScanResults];
}

- (void)runFullScan {
    [self openScanResults];
}

- (void)openScanResults {
    // 内存缓存，避免每次都从NSUserDefaults解码大数组
    static NSArray *sMemCache = nil;
    if (!sMemCache) {
        NSData *cacheData = [[NSUserDefaults standardUserDefaults] dataForKey:@"DHScanCache"];
        if (cacheData) sMemCache = [NSKeyedUnarchiver unarchiveObjectWithData:cacheData];
    }
    if (sMemCache.count > 0) {
        DHScanResultVC *vc = [DHScanResultVC new];
        vc.allResults = sMemCache;
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }
    [self showToast:@"扫描中，请稍后再打开..."];
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
    UIViewController *vc = [UIViewController new];
    vc.view = tv;
    vc.title = @"日志查看";
    vc.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"清空" style:UIBarButtonItemStylePlain target:nil action:nil];
    vc.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"清空" style:UIBarButtonItemStylePlain target:self action:@selector(clearLogs:)];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)clearLogs:(id)sender {
    [[DHLogManager sharedManager] clearTodayLog];
    [self showToast:@"日志已清空"];
}

- (void)showMonitor {
    DHMonitorManager *mgr = [DHMonitorManager shared];
    DHMonitorListVC *vc = [[DHMonitorListVC alloc] initWithStyle:UITableViewStylePlain];
    vc.title = @"动态监控";

    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = mgr.isMonitoring;
    [sw addTarget:self action:@selector(monitorSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    UIBarButtonItem *switchItem = [[UIBarButtonItem alloc] initWithCustomView:sw];
    UIBarButtonItem *listItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"list.bullet"] style:UIBarButtonItemStylePlain target:self action:@selector(showAllMonitoredMethods)];
    vc.navigationItem.rightBarButtonItems = @[switchItem, listItem];
    vc.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"清空" style:UIBarButtonItemStylePlain target:self action:@selector(clearMonitorEvents)];

    // 点击cell弹出HOOK菜单
    __weak typeof(vc) weakVC = vc;
    vc.didSelectEvent = ^(DHMonitorEvent *e) {
        // 解析类名和方法名
        NSString *sig = e.signature;
        NSString *clsName = @"";
        NSString *selName = @"";
        if ([sig hasPrefix:@"["] && [sig hasSuffix:@"]"]) {
            NSString *inner = [sig substringWithRange:NSMakeRange(1, sig.length - 2)];
            NSRange space = [inner rangeOfString:@" "];
            if (space.location != NSNotFound) {
                clsName = [inner substringToIndex:space.location];
                selName = [inner substringFromIndex:space.location + 1];
            }
        }
        if (clsName.length == 0 || selName.length == 0) return;

        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:e.signature message:@"选择HOOK返回值" preferredStyle:UIAlertControllerStyleActionSheet];
        [sheet addAction:[UIAlertAction actionWithTitle:@"返回 TRUE (YES)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [self applyMonitorHook:clsName sel:selName type:DHHookReturnTrue];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"返回 FALSE (NO)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [self applyMonitorHook:clsName sel:selName type:DHHookReturnFalse];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"返回 nil" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [self applyMonitorHook:clsName sel:selName type:DHHookReturnNil];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"拦截 / 空实现 (void)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [self applyMonitorHook:clsName sel:selName type:DHHookReturnVoid];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"返回 0" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [self applyMonitorHook:clsName sel:selName type:DHHookReturnZero];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [weakVC presentViewController:sheet animated:YES completion:nil];
    };

    // 每2秒自动刷新
    [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *t) {
        if (!weakVC.isViewLoaded || !weakVC.view.window) { [t invalidate]; return; }
        [weakVC.tableView reloadData];
    }];

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)applyMonitorHook:(NSString *)clsName sel:(NSString *)selName type:(DHHookReturnType)type {
    // 先弹出选择保存位置的菜单
    NSMutableSet *folderSet = [NSMutableSet setWithArray:[DHPatchListVC dhLoadFolders]];
    for (DHHookInfo *h in [DHHookManager sharedManager].savedHooks) {
        if (h.folderName.length) [folderSet addObject:h.folderName];
    }
    NSArray *folders = [[folderSet allObjects] sortedArrayUsingSelector:@selector(compare:)];
    
    if (folders.count == 0) {
        // 没有文件夹，直接存根目录
        [self doApplyMonitorHook:clsName sel:selName type:type folder:nil];
        return;
    }
    
    // 有文件夹，弹出选择
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"选择保存位置" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"根目录" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self doApplyMonitorHook:clsName sel:selName type:type folder:nil];
    }]];
    for (NSString *fname in folders) {
        [sheet addAction:[UIAlertAction actionWithTitle:fname style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [self doApplyMonitorHook:clsName sel:selName type:type folder:fname];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    // 找到当前最顶层的VC来present
    UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;
    [topVC presentViewController:sheet animated:YES completion:nil];
}

- (void)doApplyMonitorHook:(NSString *)clsName sel:(NSString *)selName type:(DHHookReturnType)type folder:(NSString *)folder {
    DHHookInfo *h = [DHHookInfo new];
    h.className = clsName;
    h.selectorName = selName;
    h.returnType = type;
    h.enabled = YES;
    h.folderName = folder;
    // 推断真实返回类型
    NSString *realType;
    if ([selName hasPrefix:@"set"]) realType = @"void";
    else if ([selName hasPrefix:@"is"] || [selName hasPrefix:@"has"] || [selName hasPrefix:@"should"]) realType = @"BOOL";
    else if ([selName hasPrefix:@"init"]) realType = @"id";
    else realType = @"id";
    h.realReturnType = realType;
    h.argCount = [[selName componentsSeparatedByString:@":"] count] - 1;
    [[DHHookManager sharedManager] addHook:h];
    NSString *loc = folder ?: @"根目录";
    [self showToast:[NSString stringWithFormat:@"已HOOK %@ → %@", selName, loc]];
}

- (void)showAllMonitoredMethods {
    NSArray *allMethods = [[DHMonitorManager shared] allMonitoredMethods];
    if (allMethods.count == 0) {
        [self showToast:@"没有监控中的方法"];
        return;
    }
    
    // 找出哪些已经被调用过了
    NSMutableSet *calledSignatures = [NSMutableSet new];
    for (DHMonitorEvent *e in [DHMonitorManager shared].events) {
        [calledSignatures addObject:e.signature];
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"全部监控方法 (%lu个)", (unsigned long)allMethods.count] message:nil preferredStyle:UIAlertControllerStyleAlert];
    
    // 显示前50个，太多了会崩
    NSInteger showCount = MIN(allMethods.count, 50);
    for (NSInteger i = 0; i < showCount; i++) {
        NSString *sig = allMethods[i];
        NSString *prefix = [calledSignatures containsObject:sig] ? @"✓ " : @"○ ";
        [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@%@", prefix, sig] style:UIAlertActionStyleDefault handler:nil]];
    }
    if (allMethods.count > 50) {
        [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"...还有%ld个", (long)(allMethods.count - 50)] style:UIAlertActionStyleDefault handler:nil]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    
    UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;
    [topVC presentViewController:alert animated:YES completion:nil];
}

- (void)clearMonitorEvents {
    [[DHMonitorManager shared] clearEvents];
    [self showToast:@"已清空"];
}

- (void)monitorSwitchChanged:(UISwitch *)sw {
    if (sw.on) {
        [self showToast:@"请从扫描结果页点眼睛按钮选择监控方法"];
        sw.on = NO;
    } else {
        [[DHMonitorManager shared] stop];
    }
}

- (void)resetAllConfig {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重置配置" message:@"将清除所有规则、Hook、补丁和设置，确定继续？" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定重置" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [[DHHookManager sharedManager] clearAllHooks];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"DHInterceptRules"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"DHSavedHooks"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"DHSavedPatches"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"DHPatchFolders"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"DHKeywordFolders"];
        [[NSFileManager defaultManager] removeItemAtPath:[[DHPatchListVC dhDataDir] stringByAppendingPathComponent:@"hooks.plist"] error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:[[DHPatchListVC dhDataDir] stringByAppendingPathComponent:@"patches.plist"] error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:[[DHPatchListVC dhDataDir] stringByAppendingPathComponent:@"folders.plist"] error:nil];
        [[DHHookManager sharedManager] clearAllHooks];
        [[NSUserDefaults standardUserDefaults] synchronize];
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

@implementation DHMonitorListVC

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [DHMonitorManager shared].events.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MonitorCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"MonitorCell"];
    }
    DHMonitorEvent *e = [DHMonitorManager shared].events[indexPath.row];
    NSString *countStr = [NSString stringWithFormat:@" (×%ld)", (long)e.count];
    cell.textLabel.text = [NSString stringWithFormat:@"%@%@", e.signature, countStr];
    cell.textLabel.font = [UIFont systemFontOfSize:13];
    
    // 检查这个方法有没有被HOOK
    NSString *clsName = @"";
    NSString *selName = @"";
    if ([e.signature hasPrefix:@"["] && [e.signature hasSuffix:@"]"]) {
        NSString *inner = [e.signature substringWithRange:NSMakeRange(1, e.signature.length - 2)];
        NSRange space = [inner rangeOfString:@" "];
        if (space.location != NSNotFound) {
            clsName = [inner substringToIndex:space.location];
            selName = [inner substringFromIndex:space.location + 1];
        }
    }
    
    NSString *hookInfo = @"";
    for (DHHookInfo *h in [DHHookManager sharedManager].savedHooks) {
        if ([h.className isEqualToString:clsName] && [h.selectorName isEqualToString:selName] && h.enabled) {
            NSString *hookRet = @"";
            switch (h.returnType) {
                case DHHookReturnTrue: hookRet = @"YES"; break;
                case DHHookReturnFalse: hookRet = @"NO"; break;
                case DHHookReturnNil: hookRet = @"nil"; break;
                case DHHookReturnVoid: hookRet = @"void"; break;
                case DHHookReturnZero: hookRet = @"0"; break;
                default: hookRet = @"自定义"; break;
            }
            hookInfo = [NSString stringWithFormat:@" / HOOK: %@", hookRet];
            break;
        }
    }
    
    cell.detailTextLabel.text = [NSString stringWithFormat:@"真实: %@%@", e.returnValue ?: @"无", hookInfo];
    cell.detailTextLabel.textColor = hookInfo.length ? [UIColor systemRedColor] : [UIColor systemBlueColor];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:11];
    
    // 已经HOOK过的方法高亮显示
    if (hookInfo.length) {
        cell.backgroundColor = [UIColor colorWithRed:1.0 green:0.95 blue:0.9 alpha:1.0];
    } else {
        cell.backgroundColor = [UIColor whiteColor];
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    DHMonitorEvent *e = [DHMonitorManager shared].events[indexPath.row];
    if (self.didSelectEvent) self.didSelectEvent(e);
}

@end
