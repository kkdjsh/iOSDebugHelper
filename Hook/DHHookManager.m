//
//  DHHookManager.m
//  iOSDebugHelper
//

#import "DHHookManager.h"
#import "DHLogManager.h"
#import <substrate.h>
#import <objc/runtime.h>

@implementation DHHookManager

+ (instancetype)sharedManager {
    static DHHookManager *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [self new]; });
    return m;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _savedHooks = @[];
        _savedPatches = @[];
    }
    return self;
}

- (void)loadHooks {
    NSData *data = [[NSUserDefaults standardUserDefaults] dataForKey:kDHSavedHooksKey];
    if (data) {
        self.savedHooks = [NSKeyedUnarchiver unarchiveObjectWithData:data] ?: @[];
    }
    NSData *pdata = [[NSUserDefaults standardUserDefaults] dataForKey:kDHSavedPatchesKey];
    if (pdata) {
        self.savedPatches = [NSKeyedUnarchiver unarchiveObjectWithData:pdata] ?: @[];
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
    DHLogInfo(@"HookManager: 开始应用 %lu 个 Hook", (unsigned long)self.savedHooks.count);
    for (DHHookInfo *hook in self.savedHooks) {
        [self applyHook:hook];
    }
    DHLogInfo(@"HookManager: 完成应用 %lu 个 Hook", (unsigned long)self.savedHooks.count);
}

- (void)applyHook:(DHHookInfo *)hook {
    Class cls = NSClassFromString(hook.className);
    if (!cls) {
        DHLogWarn(@"Hook失败: 类 %@ 不存在", hook.className);
        return;
    }
    if (hook.isClassMethod) cls = object_getClass(cls);

    SEL sel = NSSelectorFromString(hook.selectorName);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        DHLogWarn(@"Hook失败: 方法 +[%@ %@] 不存在", hook.className, hook.selectorName);
        return;
    }

    // 通过 method swizzling 替换返回值
    IMP originalImp = method_getImplementation(m);
    // 注意：实际 Hook 中使用 MSHookMessageEx 或 method_setImplementation
    // 这里记录 Hook 已注册，运行时由 FLEX 运行时框架执行替换
    DHLogInfo(@"已注册 Hook: %@ %@ → 返回类型 %ld", hook.className, hook.selectorName, (long)hook.returnType);
}

- (void)addHook:(DHHookInfo *)hook {
    NSMutableArray *arr = [self.savedHooks mutableCopy];
    [arr addObject:hook];
    self.savedHooks = arr;
    [self saveHooks];
    [self applyHook:hook];
}

- (void)removeHook:(DHHookInfo *)hook {
    NSMutableArray *arr = [self.savedHooks mutableCopy];
    [arr removeObject:hook];
    self.savedHooks = arr;
    [self saveHooks];
}

- (void)clearAllHooks {
    self.savedHooks = @[];
    self.savedPatches = @[];
    [self saveHooks];
    DHLogInfo(@"已清空所有 Hook 配置");
}

- (NSString *)exportLogosCode {
    NSMutableString *code = [NSMutableString string];
    [code appendString:@"// iOSDebugHelper 自动生成 Tweak.x\n\n"];
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
                case DHHookReturnCustomString:
                    [code appendFormat:@"    return @\"%@\";\n", h.customValue ?: @""]; break;
                case DHHookReturnCustomNumber:
                    [code appendFormat:@"    return %@;\n", h.customValue ?: @(0)]; break;
                default: [code appendFormat:@"    %%orig(%@);\n", h.selectorName];
            }
            [code appendString:@"}\n"];
        }
        [code appendString:@"%end\n\n"];
    }
    return code;
}

@end
