//
//  DHHookManager.m
//  iOSDebugHelper
//  真正实现 method swizzling，替换方法返回值
//

#import "DHHookManager.h"
#import "DHLogManager.h"
#import <objc/runtime.h>

// 保存原始IMP，用于取消Hook时恢复
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
        if (hook.enabled) [self applyHook:hook];
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
        DHLogWarn(@"Hook失败: 方法 %@ %@ 不存在", hook.className, hook.selectorName);
        return;
    }

    NSString *key = [NSString stringWithFormat:@"%@-%@", hook.className, hook.selectorName];
    IMP originalImp = method_getImplementation(m);
    if (!sOriginalIMPs[key]) {
        sOriginalIMPs[key] = [NSValue valueWithPointer:originalImp];
    }

    // 根据返回类型构造block
    id block = nil;
    switch (hook.returnType) {
        case DHHookReturnTrue: {
            block = ^id(id self, SEL _cmd) { return (__bridge id)kCFBooleanTrue; };
            break;
        }
        case DHHookReturnFalse: {
            block = ^id(id self, SEL _cmd) { return nil; };
            break;
        }
        case DHHookReturnNil: {
            block = ^id(id self, SEL _cmd) { return nil; };
            break;
        }
        case DHHookReturnZero: {
            block = ^id(id self, SEL _cmd) { return nil; };
            break;
        }
        case DHHookReturnCustomString: {
            block = ^id(id self, SEL _cmd) { return hook.customValue ?: @""; };
            break;
        }
        case DHHookReturnCustomNumber: {
            NSNumber *num = [hook.customValue isKindOfClass:[NSNumber class]] ? hook.customValue : @([hook.customValue doubleValue]);
            block = ^id(id self, SEL _cmd) { return num; };
            break;
        }
        default: {
            block = ^id(id self, SEL _cmd) {
                IMP orig = [sOriginalIMPs[key] pointerValue];
                return ((id(*)(id, SEL))orig)(self, _cmd);
            };
            break;
        }
    }

    IMP newImp = imp_implementationWithBlock(block);
    method_setImplementation(m, newImp);
    DHLogInfo(@"Hook成功: %@ %@ → 返回类型 %ld", hook.className, hook.selectorName, (long)hook.returnType);
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
    if (m) {
        method_setImplementation(m, [origVal pointerValue]);
        DHLogInfo(@"Hook已禁用: %@ %@", hook.className, hook.selectorName);
    }
}

- (void)addHook:(DHHookInfo *)hook {
    hook.enabled = YES;
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
    if (hook.enabled) {
        [self applyHook:hook];
    } else {
        [self disableHook:hook];
    }
    [self saveHooks];
}

- (void)clearAllHooks {
    for (DHHookInfo *h in self.savedHooks) [self disableHook:h];
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
