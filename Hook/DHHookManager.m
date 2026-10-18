//
//  DHHookManager.m
//  iOSDebugHelper
//  真正实现 method swizzling，根据方法返回类型正确替换返回值
//

#import "DHHookManager.h"
#import "DHLogManager.h"
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

static NSMutableDictionary *sOriginalIMPs;

@implementation DHHookManager

+ (void)initialize {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sOriginalIMPs = [NSMutableDictionary new]; });
}

+ (instancetype)sharedManager {
    static DHHookManager *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [self new]; });
    return m;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self loadHooks];
    }
    return self;
}

- (void)loadHooks {
    NSData *data = [[NSUserDefaults standardUserDefaults] dataForKey:kDHSavedHooksKey];
    if (data) {
        @try {
            NSArray *loaded = [NSKeyedUnarchiver unarchiveObjectWithData:data];
            if (loaded) self.savedHooks = loaded;
        } @catch (NSException *e) {}
    }
    NSData *pdata = [[NSUserDefaults standardUserDefaults] dataForKey:kDHSavedPatchesKey];
    if (pdata) {
        @try {
            NSArray *loaded = [NSKeyedUnarchiver unarchiveObjectWithData:pdata];
            if (loaded) self.savedPatches = loaded;
        } @catch (NSException *e) {}
    }
}

- (void)saveHooks {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.savedHooks];
    [[NSUserDefaults standardUserDefaults] setObject:data forKey:kDHSavedHooksKey];
    NSData *pdata = [NSKeyedArchiver archivedDataWithRootObject:self.savedPatches];
    [[NSUserDefaults standardUserDefaults] setObject:pdata forKey:kDHSavedPatchesKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)applyEnabledHooks {
    [self loadHooks];
    // 检查是否有未确认的hook（上次启动没撑过5秒）
    NSArray *pendingKeys = [[NSUserDefaults standardUserDefaults] arrayForKey:@"DHPendingTestKeys"];
    if (pendingKeys.count > 0) {
        // 上次闪退了，禁用这些hook
        for (DHHookInfo *h in self.savedHooks) {
            NSString *k = [NSString stringWithFormat:@"%@|%@", h.className, h.selectorName];
            if ([pendingKeys containsObject:k]) {
                h.enabled = NO;
            }
        }
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"DHPendingTestKeys"];
        [self saveHooks];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"安全保护" message:@"检测到上次新增补丁导致闪退，已自动关闭" preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
            [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:a animated:YES completion:nil];
        });
    }
    DHLogInfo(@"HookManager: 开始应用 %lu 个 Hook", (unsigned long)self.savedHooks.count);
    // 读取文件夹开关状态
    NSDictionary *folderStates = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"DHFolderSwitchStates"];
    NSMutableArray *newPending = [NSMutableArray new];
    for (DHHookInfo *hook in self.savedHooks) {
        if (hook.folderName.length > 0) {
            NSNumber *state = folderStates[hook.folderName];
            if (state) hook.enabled = [state boolValue];
        }
        if (hook.enabled) {
            [self applyHook:hook];
            // 如果这个hook是新增未确认的，加入pending
            if (hook.isPending) {
                NSString *k = [NSString stringWithFormat:@"%@|%@", hook.className, hook.selectorName];
                [newPending addObject:k];
            }
        }
    }
    // 保存pending标记（5秒后清除）
    if (newPending.count > 0) {
        [[NSUserDefaults standardUserDefaults] setObject:newPending forKey:@"DHPendingTestKeys"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            // 5秒没崩，清除pending标记
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"DHPendingTestKeys"];
            for (DHHookInfo *h in self.savedHooks) h.isPending = NO;
            [self saveHooks];
        });
    }
    [self saveHooks];
}

- (void)applyHook:(DHHookInfo *)hook {
    Class cls = NSClassFromString(hook.className);
    if (!cls) { DHLogWarn(@"Hook失败: 类 %@ 不存在", hook.className); return; }
    if (hook.isClassMethod) cls = object_getClass(cls);

    SEL sel = NSSelectorFromString(hook.selectorName);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) { DHLogWarn(@"Hook失败: 方法 %@ %@ 不存在", hook.className, hook.selectorName); return; }

    NSString *key = [NSString stringWithFormat:@"%@-%@", hook.className, hook.selectorName];
    IMP originalImp = method_getImplementation(m);
    if (!sOriginalIMPs[key]) sOriginalIMPs[key] = [NSValue valueWithPointer:originalImp];

    // 获取方法返回类型编码
    const char *retType = method_copyReturnType(m);
    NSString *typeStr = [NSString stringWithUTF8String:retType];
    free((void *)retType);

    IMP newImp = NULL;

    if ([typeStr isEqualToString:@"v"]) {
        // void 返回 - 直接什么都不做（跳过原方法）
        newImp = imp_implementationWithBlock(^void(id self, SEL _cmd) {});
    } else if ([typeStr isEqualToString:@"B"] || [typeStr isEqualToString:@"c"] || [typeStr isEqualToString:@"C"]) {
        // BOOL / char / unsigned char
        BOOL ret = (hook.returnType == DHHookReturnTrue);
        if (hook.returnType == DHHookReturnCustomNumber) ret = [hook.customValue boolValue];
        newImp = imp_implementationWithBlock(^BOOL(id self, SEL _cmd) { return ret; });
    } else if ([typeStr isEqualToString:@"i"] || [typeStr isEqualToString:@"s"] || [typeStr isEqualToString:@"l"] || [typeStr isEqualToString:@"q"]) {
        // int / short / long / long long
        long long ret = 0;
        if (hook.returnType == DHHookReturnTrue) ret = 1;
        else if (hook.returnType == DHHookReturnCustomNumber) ret = [hook.customValue longLongValue];
        newImp = imp_implementationWithBlock(^long long(id self, SEL _cmd) { return ret; });
    } else if ([typeStr isEqualToString:@"f"] || [typeStr isEqualToString:@"d"]) {
        // float / double
        double ret = 0;
        if (hook.returnType == DHHookReturnTrue) ret = 1.0;
        else if (hook.returnType == DHHookReturnCustomNumber) ret = [hook.customValue doubleValue];
        newImp = imp_implementationWithBlock(^double(id self, SEL _cmd) { return ret; });
    } else if ([typeStr hasPrefix:@"@"]) {
        // 对象类型 (id, NSObject*, NSString*, etc.)
        __block id ret = nil;
        if (hook.returnType == DHHookReturnTrue) ret = (__bridge id)kCFBooleanTrue;
        else if (hook.returnType == DHHookReturnFalse) ret = nil;
        else if (hook.returnType == DHHookReturnNil) ret = nil;
        else if (hook.returnType == DHHookReturnZero) ret = nil;
        else if (hook.returnType == DHHookReturnCustomString) ret = hook.customValue ?: @"";
        else if (hook.returnType == DHHookReturnCustomNumber) ret = hook.customValue;
        newImp = imp_implementationWithBlock(^id(id self, SEL _cmd) { return ret; });
    } else if ([typeStr isEqualToString:@"#"]) {
        // Class 返回
        Class ret = Nil;
        if (hook.returnType == DHHookReturnTrue) ret = [NSObject class];
        newImp = imp_implementationWithBlock(^Class(id self, SEL _cmd) { return ret; });
    } else {
        // 未知类型，默认返回nil/0
        newImp = imp_implementationWithBlock(^id(id self, SEL _cmd) { return nil; });
    }

    method_setImplementation(m, newImp);
    DHLogInfo(@"Hook成功: %@ %@ retType=%@", hook.className, hook.selectorName, typeStr);
}

- (void)disableHook:(DHHookInfo *)hook {
    NSString *key = [NSString stringWithFormat:@"%@-%@", hook.className, hook.selectorName];
    NSValue *origVal = sOriginalIMPs[key];
    if (!origVal) return;
    Class cls = NSClassFromString(hook.className);
    if (!cls) return;
    if (hook.isClassMethod) cls = object_getClass(cls);
    SEL sel = NSSelectorFromString(hook.selectorName);
    Method m = class_getInstanceMethod(cls, sel);
    if (m) method_setImplementation(m, [origVal pointerValue]);
}

- (void)addHook:(DHHookInfo *)hook {
    hook.enabled = YES;
    hook.isPending = YES;
    NSMutableArray *arr = [self.savedHooks mutableCopy];
    [arr addObject:hook];
    self.savedHooks = arr;
    [self saveHooks];
    [self applyHook:hook];
}

- (void)removeHook:(DHHookInfo *)hook {
    [self disableHook:hook];
    NSMutableArray *arr = [self.savedHooks mutableCopy];
    [arr removeObject:hook];
    self.savedHooks = arr;
    [self saveHooks];
}

- (void)toggleHook:(DHHookInfo *)hook {
    hook.enabled = !hook.enabled;
    if (hook.enabled) [self applyHook:hook];
    else [self disableHook:hook];
    [self saveHooks];
}

- (void)clearAllHooks {
    for (DHHookInfo *h in self.savedHooks) [self disableHook:h];
    self.savedHooks = @[];
    self.savedPatches = @[];
    [self saveHooks];
}

- (NSString *)exportLogosCode {
    NSMutableString *code = [NSMutableString string];
    [code appendString:@"// iOSDebugHelper Tweak.x\n\n"];
    NSMutableSet *classes = [NSMutableSet new];
    for (DHHookInfo *h in self.savedHooks) [classes addObject:h.className];
    for (NSString *cls in classes) {
        [code appendFormat:@"%%hook %@\n", cls];
        for (DHHookInfo *h in self.savedHooks) {
            if (![h.className isEqualToString:cls]) continue;
            NSString *prefix = h.isClassMethod ? @"+" : @"-";
            [code appendFormat:@"%@(void)%@ {\n", prefix, h.selectorName];
            switch (h.returnType) {
                case DHHookReturnTrue:  [code appendString:@"    return YES;\n"]; break;
                case DHHookReturnFalse: [code appendString:@"    return NO;\n"]; break;
                case DHHookReturnNil:   [code appendString:@"    return nil;\n"]; break;
                case DHHookReturnZero:  [code appendString:@"    return 0;\n"]; break;
                case DHHookReturnCustomString: [code appendFormat:@"    return @\"%@\";\n", h.customValue ?: @""]; break;
                case DHHookReturnCustomNumber: [code appendFormat:@"    return %@;\n", h.customValue ?: @(0)]; break;
                default: break;
            }
            [code appendString:@"}\n"];
        }
        [code appendString:@"%end\n\n"];
    }
    return code;
}

@end
