//
//  DHKeywordVC.m
//  iOSDebugHelper
//

#import "DHKeywordVC.h"

@interface DHKeywordFileVC : UITableViewController
@property (nonatomic, strong) NSMutableArray *folders;
@property (nonatomic, assign) NSInteger idx;
@end

@interface DHKeywordEditVC : UIViewController
@property (nonatomic, strong) NSMutableArray *folders;
@property (nonatomic, assign) NSInteger folderIdx;
@property (nonatomic, assign) NSInteger fileIdx;
@end

#pragma mark - 文件夹列表
@implementation DHKeywordFolderVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"关键词词库";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addFolder)];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"kf"];
}
- (NSMutableArray *)folders {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:@"DHKeywordFolders"];
    return saved ? [saved mutableCopy] : [NSMutableArray new];
}
- (void)save:(NSMutableArray *)f { [[NSUserDefaults standardUserDefaults] setObject:f forKey:@"DHKeywordFolders"]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (void)addFolder {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"新建文件夹" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = @"文件夹名"; }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *name = a.textFields[0].text;
        if (!name.length) return;
        NSMutableArray *f = [self folders];
        for (NSDictionary *e in f) { if ([e[@"name"] isEqualToString:name]) { [self toast:@"名字已存在"]; return; } }
        [f addObject:[@{@"name":name, @"files":@[]} mutableCopy]];
        [self save:f]; [self.tableView reloadData];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return [self folders].count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"kf" forIndexPath:ip];
    c.textLabel.text = [self folders][ip.row][@"name"];
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    DHKeywordFileVC *vc = [DHKeywordFileVC new];
    vc.folders = [self folders];
    vc.idx = ip.row;
    [self.navigationController pushViewController:vc animated:YES];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction *a, UIView *v, void(^d)(BOOL)) {
        NSMutableArray *f = [self folders];
        [f removeObjectAtIndex:ip.row];
        [self save:f]; d(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}
- (void)toast:(NSString *)m {
    UIAlertController *t = [UIAlertController alertControllerWithTitle:nil message:m preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:t animated:YES completion:^{ dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [t dismissViewControllerAnimated:YES completion:nil]; }); }];
}
@end

#pragma mark - 文件列表
@implementation DHKeywordFileVC
- (NSArray *)files { return self.folders[self.idx][@"files"]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.folders[self.idx][@"name"];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addFile)];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"kfile"];
}
- (void)save { [[NSUserDefaults standardUserDefaults] setObject:self.folders forKey:@"DHKeywordFolders"]; }
- (void)addFile {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"新建文件" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = @"文件名"; }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *name = a.textFields[0].text;
        if (!name.length) return;
        NSMutableDictionary *folder = [self.folders[self.idx] mutableCopy];
        NSMutableArray *files = [folder[@"files"] mutableCopy];
        [files addObject:[@{@"name":name, @"content":@""} mutableCopy]];
        folder[@"files"] = files;
        self.folders[self.idx] = folder;
        [self save]; [self.tableView reloadData];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.files.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"kfile" forIndexPath:ip];
    c.textLabel.text = self.files[ip.row][@"name"];
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    DHKeywordEditVC *vc = [DHKeywordEditVC new];
    vc.folders = self.folders;
    vc.folderIdx = self.idx;
    vc.fileIdx = ip.row;
    [self.navigationController pushViewController:vc animated:YES];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction *a, UIView *v, void(^d)(BOOL)) {
        NSMutableDictionary *folder = [self.folders[self.idx] mutableCopy];
        NSMutableArray *files = [folder[@"files"] mutableCopy];
        [files removeObjectAtIndex:ip.row];
        folder[@"files"] = files;
        self.folders[self.idx] = folder;
        [self save]; d(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}
@end

#pragma mark - 编辑
@implementation DHKeywordEditVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.title = self.folders[self.folderIdx][@"files"][self.fileIdx][@"name"];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    self.tv = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tv.font = [UIFont systemFontOfSize:14];
    self.tv.text = self.folders[self.folderIdx][@"files"][self.fileIdx][@"content"];
    [self.view addSubview:self.tv];
}
- (void)save {
    NSMutableDictionary *file = [self.folders[self.folderIdx][@"files"][self.fileIdx] mutableCopy];
    file[@"content"] = self.tv.text;
    NSMutableArray *files = [self.folders[self.folderIdx][@"files"] mutableCopy];
    files[self.fileIdx] = file;
    NSMutableDictionary *folder = [self.folders[self.folderIdx] mutableCopy];
    folder[@"files"] = files;
    self.folders[self.folderIdx] = folder;
    [[NSUserDefaults standardUserDefaults] setObject:self.folders forKey:@"DHKeywordFolders"];
    [self.navigationController popViewControllerAnimated:YES];
}
@end
