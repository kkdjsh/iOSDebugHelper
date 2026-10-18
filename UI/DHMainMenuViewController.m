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
#import "DHKeywordVC.h"
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

- (NSArray *)folderNames {
    NSMutableSet *set = [NSMutableSet setWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"DHPatchFolders"] ?: @[]];
    for (DHHookInfo *h in [DHHookManager sharedManager].savedHooks) {
        if (h.folderName.length) [set addObject:h.folderName];
    }
    return [[set allObjects] sortedArrayUsingSelector:@selector(compare:)];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.currentFolder ?: @"补丁管理";
    UIBarButtonItem *addBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addMenu)];
    UIBarButtonItem *moreBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:self action:@selector(moreMenu)];
    self.navigationItem.rightBarButtonItems = @[addBtn, moreBtn];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
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
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:ip];

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
        case DHHookReturnZero: retStr = @"→0"; break;
        case DHHookReturnCustomString: retStr = [NSString stringWithFormat:@"→\"%@\"", h.customValue ?: @""]; break;
        case DHHookReturnCustomNumber: retStr = [NSString stringWithFormat:@"→%@", h.customValue ?: @0]; break;
        default: retStr = @""; break;
    }
    c.textLabel.text = [NSString stringWithFormat:@"%@[%@ %@] %@", h.isClassMethod ? @"+" : @"-", h.className, h.selectorName, retStr];
    c.textLabel.font = [UIFont systemFontOfSize:11];
    c.textLabel.numberOfLines = 1;
    c.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    c.accessoryType = UITableViewCellAccessoryNone;
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
        UITableViewRowAction *enableAll = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleNormal title:@"启用全部" handler:^(UITableViewRowAction *a, NSIndexPath *idx) {
            for (DHHookInfo *h in [DHHookManager sharedManager].savedHooks) {
                if ([h.folderName isEqualToString:fname] && !h.enabled) [[DHHookManager sharedManager] toggleHook:h];
            }
            [self.tableView reloadData];
        }];
        UITableViewRowAction *disableAll = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleNormal title:@"关闭全部" handler:^(UITableViewRowAction *a, NSIndexPath *idx) {
            for (DHHookInfo *h in [DHHookManager sharedManager].savedHooks) {
                if ([h.folderName isEqualToString:fname] && h.enabled) [[DHHookManager sharedManager] toggleHook:h];
            }
            [self.tableView reloadData];
        }];
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
                NSMutableArray *folders = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"DHPatchFolders"] ?: @[]];
                [folders removeObject:fname];
                [[NSUserDefaults standardUserDefaults] setObject:folders forKey:@"DHPatchFolders"];
                [self.tableView reloadData];
            }]];
            [self presentViewController:confirm animated:YES completion:nil];
        }];
        return @[del, disableAll, enableAll];
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

- (void)addMenu {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"新建" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"新建补丁" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) { [self addHook]; }]];
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
        NSMutableArray *folders = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"DHPatchFolders"] ?: @[]];
        if (![folders containsObject:name]) {
            [folders addObject:name];
            [[NSUserDefaults standardUserDefaults] setObject:folders forKey:@"DHPatchFolders"];
        }
        [self.tableView reloadData];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - 导入导出

- (void)moreMenu {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"更多" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"导出配置" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self exportMenu]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"导入配置" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self importMenu]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
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
    NSMutableArray *folders = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"DHPatchFolders"] ?: @[]];
    NSString *finalName = folderName;
    NSInteger suffix = 1;
    while ([folders containsObject:finalName]) {
        finalName = [NSString stringWithFormat:@"%@_%ld", folderName, (long)suffix++];
    }
    [folders addObject:finalName];
    [[NSUserDefaults standardUserDefaults] setObject:folders forKey:@"DHPatchFolders"];

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
        h.enabled = NO;
        [[DHHookManager sharedManager] addHook:h];
        // addHook会自动enable，需要立即关掉
        [[DHHookManager sharedManager] toggleHook:h];
        count++;
    }
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
    NSInteger _searchScope; // 0=全部 1=类名 2=方法名
    BOOL _filterSystemClasses; // 默认YES
    BOOL _filterBOOLOnly;
    BOOL _filterHasArgs;
    BOOL _filterClassMethods;
    BOOL _filterInstanceMethods;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"扫描结果";
    _filterSystemClasses = YES;
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"批量复制" style:UIBarButtonItemStyleDone target:self action:@selector(batchCopy)],
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"bolt.fill"] style:UIBarButtonItemStylePlain target:self action:@selector(openKeywordMenu)],
    ];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
    self.tableView.rowHeight = 44;
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
    NSString *retType = r.returnType ?: @"id";
    if ([r.methodName isEqualToString:@"(class)"]) {
        c.textLabel.text = [NSString stringWithFormat:@"+ (Class)%@", r.className];
    } else {
        c.textLabel.text = [NSString stringWithFormat:@"- (%@)%@", retType, r.methodName];
    }
    c.textLabel.font = [UIFont systemFontOfSize:12];
    c.textLabel.numberOfLines = 1;
    c.textLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    NSString *img = r.imageName ?: @"";
    if (img.length) {
        c.detailTextLabel.text = [NSString stringWithFormat:@"In Class: %@ [%@]", r.className, img];
    } else {
        c.detailTextLabel.text = [NSString stringWithFormat:@"In Class: %@", r.className];
    }
    c.detailTextLabel.font = [UIFont systemFontOfSize:10];
    c.detailTextLabel.textColor = [UIColor grayColor];
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
    // 从NSUserDefaults读取所有文件夹
    NSMutableSet *folderSet = [NSMutableSet setWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"DHPatchFolders"] ?: @[]];
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
    h.realReturnType = r.returnType ?: @"id";
    h.argCount = [[selName componentsSeparatedByString:@":"] count] - 1;
    [[DHHookManager sharedManager] addHook:h];
    NSString *loc = folder ?: @"根目录";
    [self showToast:[NSString stringWithFormat:@"补丁已保存至 %@", loc]];
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

- (void)filterBtnTapped:(UIButton *)btn {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"筛选" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *titles = @[
        _searchScope == 0 ? @"✓ 全部" : @"  全部",
        _searchScope == 1 ? @"✓ 仅类名" : @"  仅类名",
        _searchScope == 2 ? @"✓ 仅方法名" : @"  仅方法名",
        @"",
        _filterSystemClasses ? @"✓ 过滤系统类" : @"  过滤系统类",
        _filterBOOLOnly ? @"✓ 仅看BOOL方法" : @"  仅看BOOL方法",
        _filterHasArgs ? @"✓ 仅看带参方法" : @"  仅看带参方法",
    ];
    for (NSInteger i = 0; i < titles.count; i++) {
        if (i == 3) { [sheet addAction:[UIAlertAction actionWithTitle:@"———" style:UIAlertActionStyleDestructive handler:nil]]; continue; }
        [sheet addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            if (i < 3) self->_searchScope = i;
            else if (i == 4) self->_filterSystemClasses = !self->_filterSystemClasses;
            else if (i == 5) self->_filterBOOLOnly = !self->_filterBOOLOnly;
            else if (i == 6) self->_filterHasArgs = !self->_filterHasArgs;
            [self filterBtnTapped:btn]; // 刷新菜单
            [self applyFilter];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
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
    if (_filterSystemClasses) {
        NSString *cn = r.className;
        if ([cn hasPrefix:@"NS"] || [cn hasPrefix:@"UI"] || [cn hasPrefix:@"CF"] ||
            [cn hasPrefix:@"_"] || [cn hasPrefix:@"__"] || [cn hasPrefix:@"CA"]) return NO;
    }
    if (_filterBOOLOnly) {
        if (![r.returnType caseInsensitiveCompare:@"bool"] == NSOrderedSame) return NO;
    }
    if (_filterHasArgs) {
        if (![r.methodName containsString:@":"]) return NO;
    }
    return YES;
}

- (void)applyKeywordFolder:(NSDictionary *)folder {
    NSString *content = folder[@"content"] ?: @"";
    NSArray *parts = [content componentsSeparatedByCharactersInSet:
        [NSCharacterSet characterSetWithCharactersInString:@",，、/\\ \n\t"]];
    NSMutableSet *kws = [NSMutableSet new];
    for (NSString *p in parts) {
        NSString *t = [p stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (t.length) [kws addObject:t];
    }
    if (kws.count == 0) { [self showToast:@"词库为空"]; return; }

    NSInteger scope = _searchScope;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *result = [NSMutableArray new];
        for (DHScannerResult *r in self.allResults) {
            BOOL hit = NO;
            for (NSString *kw in kws) {
                if (scope == 1) {
                    if ([r.className rangeOfString:kw options:NSCaseInsensitiveSearch].location != NSNotFound) { hit = YES; break; }
                } else if (scope == 2) {
                    if ([r.methodName rangeOfString:kw options:NSCaseInsensitiveSearch].location != NSNotFound) { hit = YES; break; }
                } else {
                    if ([r.className rangeOfString:kw options:NSCaseInsensitiveSearch].location != NSNotFound ||
                        [r.methodName rangeOfString:kw options:NSCaseInsensitiveSearch].location != NSNotFound) { hit = YES; break; }
                }
            }
            if (!hit) continue;
            if ([self passFunnelFilter:r]) [result addObject:r];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.filteredResults = result;
            [self.tableView reloadData];
            [self showToast:[NSString stringWithFormat:@"%@ 匹配到 %lu 条", folder[@"name"], (unsigned long)result.count]];
        });
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
    _searchDebounce = [NSTimer scheduledTimerWithTimeInterval:0.3 repeats:NO block:^(NSTimer *t) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSMutableArray *result = [NSMutableArray new];
            for (DHScannerResult *r in all) {
                // 关键词过滤
                if (kw.length) {
                    if (scope == 1) {
                        if (![r.className.lowercaseString containsString:kw]) continue;
                    } else if (scope == 2) {
                        if (![r.methodName.lowercaseString containsString:kw]) continue;
                    } else {
                        if (![r.className.lowercaseString containsString:kw] && ![r.methodName.lowercaseString containsString:kw]) continue;
                    }
                }
                // 过滤系统类
                if (fSys) {
                    NSString *cn = r.className;
                    if ([cn hasPrefix:@"NS"] || [cn hasPrefix:@"UI"] || [cn hasPrefix:@"CF"] ||
                        [cn hasPrefix:@"_"] || [cn hasPrefix:@"__"] || [cn hasPrefix:@"CA"]) continue;
                }
                // 仅看BOOL方法（方法名以is/has/should开头）
                if (fBool) {
                    NSString *mn = r.methodName.lowercaseString;
                    if (![mn hasPrefix:@"is"] && ![mn hasPrefix:@"has"] && ![mn hasPrefix:@"should"]) continue;
                }
                // 仅看带参方法
                if (fArgs) {
                    if (![r.methodName containsString:@":"]) continue;
                }
                [result addObject:r];
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
                @{@"title": @"关键词词库",   @"icon": @"text.badge.star", @"action": @"openKeywords"},
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
    } else if ([action isEqualToString:@"openGlobalScan"]) {
        [self runFullScan];
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
