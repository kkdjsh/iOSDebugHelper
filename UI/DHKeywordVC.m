//
//  DHKeywordVC.m
//  iOSDebugHelper
//  简化版：文件夹直接就是编辑页，没有中间文件层
//

#import "DHKeywordVC.h"

@interface DHKeywordEditVC : UIViewController
@property (nonatomic, strong) NSMutableArray *folders;
@property (nonatomic, assign) NSInteger idx;
@property (nonatomic, strong) UITextView *tv;
@end

#pragma mark - 文件夹列表
@interface DHKeywordFolderVC () <UISearchBarDelegate>
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSMutableArray *filtered;
@end

@implementation DHKeywordFolderVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"关键词词库";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addFolder)];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"kf"];
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    self.searchBar.placeholder = @"搜索词库名...";
    self.searchBar.delegate = self;
    self.tableView.tableHeaderView = self.searchBar;
    self.filtered = [NSMutableArray new];
}
- (NSMutableArray *)folders {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:@"DHKeywordFolders"];
    return saved ? [saved mutableCopy] : [NSMutableArray new];
}
- (void)save:(NSMutableArray *)f { [[NSUserDefaults standardUserDefaults] setObject:f forKey:@"DHKeywordFolders"]; [[NSUserDefaults standardUserDefaults] synchronize]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self doFilter]; [self.tableView reloadData]; }
- (void)doFilter {
    NSString *q = self.searchBar.text.lowercaseString;
    if (!q.length) { self.filtered = [[self folders] mutableCopy]; return; }
    self.filtered = [NSMutableArray new];
    for (NSDictionary *e in [self folders]) {
        if ([e[@"name"].lowercaseString containsString:q]) [self.filtered addObject:e];
    }
}
- (void)searchBar:(UISearchBar *)s textDidChange:(NSString *)t { [self doFilter]; [self.tableView reloadData]; }
- (void)addFolder {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"新建词库" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = @"词库名，如：广告拦截"; }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *name = a.textFields[0].text;
        if (!name.length) return;
        NSMutableArray *f = [self folders];
        for (NSDictionary *e in f) { if ([e[@"name"] isEqualToString:name]) { [self toast:@"名字已存在"]; return; } }
        [f addObject:[@{@"name":name, @"content":@""} mutableCopy]];
        [self save:f]; [self doFilter]; [self.tableView reloadData];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.filtered.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"kf" forIndexPath:ip];
    c.textLabel.text = self.filtered[ip.row][@"name"];
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    DHKeywordEditVC *vc = [DHKeywordEditVC new];
    vc.folders = [self folders];
    // find real index
    NSString *name = self.filtered[ip.row][@"name"];
    NSInteger realIdx = 0;
    for (NSInteger i = 0; i < [self folders].count; i++) {
        if ([self folders][i][@"name"] isEqualToString:name]) { realIdx = i; break; }
    }
    vc.idx = realIdx;
    [self.navigationController pushViewController:vc animated:YES];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    UIContextualAction *rename = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"重命名" handler:^(UIContextualAction *a, UIView *v, void(^d)(BOOL)) {
        d(YES);
        NSString *name = self.filtered[ip.row][@"name"];
        NSMutableArray *f = [self folders];
        NSInteger realIdx = 0;
        for (NSInteger i = 0; i < f.count; i++) { if ([f[i][@"name"] isEqualToString:name]) { realIdx = i; break; } }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重命名词库" message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = f[realIdx][@"name"]; }];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            NSString *newName = alert.textFields[0].text;
            if (!newName.length) return;
            NSMutableDictionary *item = [f[realIdx] mutableCopy];
            item[@"name"] = newName;
            f[realIdx] = item;
            [self save:f]; [self doFilter]; [self.tableView reloadData];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }];
    rename.backgroundColor = [UIColor systemBlueColor];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction *a, UIView *v, void(^d)(BOOL)) {
        NSString *name = self.filtered[ip.row][@"name"];
        NSMutableArray *f = [self folders];
        NSInteger realIdx = 0;
        for (NSInteger i = 0; i < f.count; i++) { if ([f[i][@"name"] isEqualToString:name]) { realIdx = i; break; } }
        [f removeObjectAtIndex:realIdx];
        [self save:f]; d(YES);
        [self doFilter]; [self.tableView reloadData];
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del, rename]];
}
- (void)toast:(NSString *)m {
    UIAlertController *t = [UIAlertController alertControllerWithTitle:nil message:m preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:t animated:YES completion:^{ dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [t dismissViewControllerAnimated:YES completion:nil]; }); }];
}
@end

#pragma mark - 编辑（直接编辑词库内容）
@implementation DHKeywordEditVC {
    UISwitch *_regexSwitch;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.title = self.folders[self.idx][@"name"];
    UIBarButtonItem *saveBtn = [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    _regexSwitch = [[UISwitch alloc] init];
    _regexSwitch.on = [self.folders[self.idx][@"isRegex"] boolValue];
    UILabel *rl = [[UILabel alloc] init];
    rl.text = @"正则";
    rl.font = [UIFont systemFontOfSize:12];
    [rl sizeToFit];
    UIView *rg = [[UIView alloc] initWithFrame:CGRectMake(0, 0, rl.frame.size.width+8+_regexSwitch.frame.size.width, 31)];
    rl.frame = CGRectMake(0, 0, rl.frame.size.width, 31);
    _regexSwitch.frame = CGRectMake(rl.frame.size.width+8, 0, _regexSwitch.frame.size.width, 31);
    [rg addSubview:rl];
    [rg addSubview:_regexSwitch];
    UIBarButtonItem *regexBtn = [[UIBarButtonItem alloc] initWithCustomView:rg];
    self.navigationItem.rightBarButtonItems = @[saveBtn, regexBtn];
    self.tv = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tv.font = [UIFont systemFontOfSize:14];
    self.tv.text = self.folders[self.idx][@"content"];
    [self.view addSubview:self.tv];
    // 提示条
    UILabel *tip = [[UILabel alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height-44, self.view.bounds.size.width, 22)];
    tip.text = @"正则模式：每行一条正则表达式";
    tip.font = [UIFont systemFontOfSize:11];
    tip.textColor = [UIColor grayColor];
    tip.textAlignment = NSTextAlignmentCenter;
    tip.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:tip];
}
- (void)save {
    NSMutableDictionary *folder = [self.folders[self.idx] mutableCopy];
    folder[@"content"] = self.tv.text;
    folder[@"isRegex"] = @(_regexSwitch.on);
    self.folders[self.idx] = folder;
    [[NSUserDefaults standardUserDefaults] setObject:self.folders forKey:@"DHKeywordFolders"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self.navigationController popViewControllerAnimated:YES];
}
@end
