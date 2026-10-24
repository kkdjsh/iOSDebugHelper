//
//  DHMonitorManager.m
//  iOSDebugHelper
//

#import "DHMonitorManager.h"
#import "DHLogManager.h"
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

static NSMutableDictionary *g_origImpMap; // key: "class|sel" -> NSValue(IMP)
static NSMutableDictionary *g_lastHitTime; // key: "class|sel" -> NSDate
static NSMutableArray *g_eventsCache; // 内存缓存，定期写入文件
static dispatch_queue_t g_eventsQueue; // 文件读写串行队列
static NSInteger g_cacheCount = 0; // 已缓存条数
static BOOL g_monitoring = NO;
static NSMutableSet *g_trackedKeys; // 页面追踪本次 swizzle 的 "class|sel"
static BOOL g_tracking = NO;

@implementation DHMonitorEvent

- (NSDictionary *)toDict {
    return @{
        @"signature": self.signature ?: @"",
        @"returnValue": self.returnValue ?: @"",
        @"callStack": self.callStack ?: @"",
        @"time": self.time ?: [NSDate date],
        @"count": @(self.count)
    };
}

- (instancetype)initWithDict:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        self.signature = dict[@"signature"];
        self.returnValue = dict[@"returnValue"];
        self.callStack = dict[@"callStack"];
        self.time = dict[@"time"];
        self.count = [dict[@"count"] integerValue];
    }
    return self;
}

@end

@implementation DHMonitorManager

+ (instancetype)shared {
    static DHMonitorManager *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [self new];
        g_origImpMap = [NSMutableDictionary new];
        g_lastHitTime = [NSMutableDictionary new];
        g_eventsCache = [NSMutableArray new];
        g_trackedKeys = [NSMutableSet new];
        g_eventsQueue = dispatch_queue_create("com.debughelper.monitor", DISPATCH_QUEUE_SERIAL);
    });
    return s;
}

- (NSString *)eventsFilePath {
    NSString *doc = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [doc stringByAppendingPathComponent:@"iOSDebugHelper"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"monitor_events.plist"];
}

- (BOOL)isMonitoring { return g_monitoring; }

- (NSArray<DHMonitorEvent *> *)events {
    // 先把缓存里的写入文件，保证数据一致
    dispatch_sync(g_eventsQueue, ^{
        [self flushCacheToFile];
    });
    // 从文件读
    NSArray *arr = [NSArray arrayWithContentsOfFile:[self eventsFilePath]];
    NSMutableArray *result = [NSMutableArray new];
    for (NSDictionary *dict in arr) {
        [result addObject:[[DHMonitorEvent alloc] initWithDict:dict]];
    }
    return result;
}

// 把缓存写入文件
- (void)flushCacheToFile {
    if (g_eventsCache.count == 0) return;
    
    // 从文件读已有事件
    NSMutableArray *allEvents = [NSMutableArray arrayWithArray:[self eventsFromFile]];
    
    // 合并缓存里的新事件
    for (DHMonitorEvent *newEvent in g_eventsCache) {
        BOOL found = NO;
        for (NSInteger i = 0; i < allEvents.count; i++) {
            DHMonitorEvent *e = allEvents[i];
            if ([e.signature isEqualToString:newEvent.signature]) {
                // 已存在，更新
                e.count += newEvent.count;
                e.returnValue = newEvent.returnValue;
                e.time = newEvent.time;
                if (newEvent.callStack.length > 0) e.callStack = newEvent.callStack;
                found = YES;
                break;
            }
        }
        if (!found) {
            [allEvents addObject:newEvent];
        }
    }
    
    // 最多保留5000条，超过删最老的
    if (allEvents.count > 5000) {
        [allEvents removeObjectsInRange:NSMakeRange(0, allEvents.count - 5000)];
    }
    
    // 写回文件
    [self saveEventsToFile:allEvents];
    
    // 清空缓存
    [g_eventsCache removeAllObjects];
    g_cacheCount = 0;
}

- (NSArray *)eventsFromFile {
    NSArray *arr = [NSArray arrayWithContentsOfFile:[self eventsFilePath]];
    NSMutableArray *result = [NSMutableArray new];
    for (NSDictionary *dict in arr) {
        [result addObject:[[DHMonitorEvent alloc] initWithDict:dict]];
    }
    return result;
}

- (void)saveEventsToFile:(NSArray *)events {
    NSMutableArray *arr = [NSMutableArray new];
    for (DHMonitorEvent *e in events) {
        [arr addObject:[e toDict]];
    }
    [arr writeToFile:[self eventsFilePath] atomically:YES];
}

- (NSArray<NSString *> *)allMonitoredMethods {
    NSMutableArray *result = [NSMutableArray new];
    @synchronized(g_origImpMap) {
        for (NSString *key in g_origImpMap.allKeys) {
            NSRange sep = [key rangeOfString:@"|"];
            if (sep.location != NSNotFound) {
                NSString *cls = [key substringToIndex:sep.location];
                NSString *sel = [key substringFromIndex:sep.location + 1];
                [result addObject:[NSString stringWithFormat:@"[%@ %@]", cls, sel]];
            }
        }
    }
    return [result sortedArrayUsingSelector:@selector(compare:)];
}

// 通用日志IMP：支持多种返回值类型
static void dh_log_imp(id self, SEL _cmd, ...) {
    NSString *clsName = NSStringFromClass([self class]);
    NSString *selName = NSStringFromSelector(_cmd);
    NSString *key = [NSString stringWithFormat:@"%@|%@", clsName, selName];

    // 防刷屏：1秒内同key只记一次
    BOOL shouldLog = YES;
    @synchronized(g_lastHitTime) {
        NSDate *last = g_lastHitTime[key];
        NSDate *now = [NSDate date];
        if (last && [now timeIntervalSinceDate:last] < 1.0) shouldLog = NO;
        else g_lastHitTime[key] = now;
    }

    // 调原方法并获取返回值
    Method m = class_getInstanceMethod([self class], _cmd);
    const char *retType = m ? method_copyReturnType(m) : "";
    NSString *retStr = @"";
    IMP orig = [g_origImpMap[key] pointerValue];
    
    // 检测参数个数
    NSInteger argCount = 0;
    if (m) {
        argCount = method_getNumberOfArguments(m) - 2; // 减去self和_cmd
    }

    @try {
        if (argCount == 0) {
            // 无参数方法，按原来的方式调用，获取返回值
            if (retType[0] == 'B' || retType[0] == 'c') {
                // BOOL / char
                BOOL (*origFn)(id, SEL) = (BOOL(*)(id, SEL))orig;
                BOOL result = origFn(self, _cmd);
                retStr = result ? @"YES" : @"NO";
            } else if (retType[0] == 'i' || retType[0] == 's' || retType[0] == 'l' || retType[0] == 'q') {
                // int / short / long / long long
                long long (*origFn)(id, SEL) = (long long(*)(id, SEL))orig;
                long long result = origFn(self, _cmd);
                retStr = [NSString stringWithFormat:@"%lld", result];
            } else if (retType[0] == 'f') {
                // float
                float (*origFn)(id, SEL) = (float(*)(id, SEL))orig;
                float result = origFn(self, _cmd);
                retStr = [NSString stringWithFormat:@"%.4f", result];
            } else if (retType[0] == 'd') {
                // double
                double (*origFn)(id, SEL) = (double(*)(id, SEL))orig;
                double result = origFn(self, _cmd);
                retStr = [NSString stringWithFormat:@"%.4f", result];
            } else if (retType[0] == 'q' || retType[0] == 'L' || retType[0] == 'Q') {
                // unsigned long / unsigned long long
                unsigned long long (*origFn)(id, SEL) = (unsigned long long(*)(id, SEL))orig;
                unsigned long long result = origFn(self, _cmd);
                retStr = [NSString stringWithFormat:@"%llu", result];
            } else if (retType[0] == '@' || retType[0] == '#' || retType[0] == ':') {
                // id / Class / SEL 对象类型
                id (*origFn)(id, SEL) = (id(*)(id, SEL))orig;
                id result = origFn(self, _cmd);
                if (result) {
                    retStr = [NSString stringWithFormat:@"<%@: %p>", NSStringFromClass([result class]), result];
                    // 如果是字符串，直接显示内容
                    if ([result isKindOfClass:[NSString class]]) {
                        retStr = [NSString stringWithFormat:@"@\"%@\"", result];
                    }
                } else {
                    retStr = @"nil";
                }
            } else if (retType[0] == 'v') {
                // void
                ((void(*)(id, SEL))orig)(self, _cmd);
                retStr = @"(void)";
            } else if (retType[0] == '^' || retType[0] == '*') {
                // 指针类型
                void * (*origFn)(id, SEL) = (void * (*)(id, SEL))orig;
                void *result = origFn(self, _cmd);
                retStr = [NSString stringWithFormat:@"%p", result];
            } else {
                // 其他类型，默认按void调用
                ((void(*)(id, SEL))orig)(self, _cmd);
                retStr = [NSString stringWithFormat:@"(type:%c)", retType[0]];
            }
        } else {
            // 带参数方法：转换成可变参数函数指针调用，参数自动转发，不会栈不平衡
            // 这样至少不会崩溃，只是不记录具体返回值
            id (*origFn)(id, SEL, ...) = (id(*)(id, SEL, ...))orig;
            // 调用原方法，参数自动转发
            origFn(self, _cmd);
            retStr = [NSString stringWithFormat:@"(带%ld个参数)", (long)argCount];
        }
    } @catch (NSException *e) {
        retStr = [NSString stringWithFormat:@"监控异常: %@", e.name];
    } @finally {
        if (m) free((void *)retType);
    }

    if (!shouldLog) return;

    // 后台记录事件（去重+计数）
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *stack = [NSThread callStackSymbols];
        NSMutableArray *filtered = [NSMutableArray new];
        NSString *appName = [[NSBundle mainBundle] infoDictionary][@"CFBundleExecutable"] ?: @"";
        for (NSString *line in stack) {
            if (line.length < 20) continue;
            if ([line containsString:@"/System/Library/"] || [line containsString:@"libobjc"] ||
                [line containsString:@"libdyld"] || [line containsString:@"CoreFoundation"]) continue;
            if ([line containsString:appName] || [line containsString:@"GoogleMobileAds"] ||
                [line containsString:@"GDT"] || [line containsString:@"BUAd"]) {
                [filtered addObject:line];
            }
        }
        NSString *sig = [NSString stringWithFormat:@"[%@ %@]", clsName, selName];
        
        // 先加到内存缓存
        DHMonitorEvent *e = [DHMonitorEvent new];
        e.signature = sig;
        e.returnValue = retStr;
        e.callStack = filtered.count > 0 ? [filtered componentsJoinedByString:@"\n"] : @"";
        e.time = [NSDate date];
        e.count = 1;
        
        dispatch_async(g_eventsQueue, ^{
            [g_eventsCache addObject:e];
            g_cacheCount++;
            // 缓存达到1000条，批量写入文件
            if (g_cacheCount >= 1000) {
                [self flushCacheToFile];
            }
        });
    });
}

- (void)startWithResults:(NSArray<DHScannerResult *> *)results {
    if (g_monitoring) return;
    g_monitoring = YES;
    
    // 分批hook，每批1000个，避免一次性hook太多卡界面
    NSInteger batchSize = 1000;
    NSInteger total = results.count;
    NSInteger batches = (total + batchSize - 1) / batchSize;
    
    for (NSInteger i = 0; i < batches; i++) {
        NSInteger loc = i * batchSize;
        NSInteger len = MIN(batchSize, total - loc);
        NSArray *batch = [results subarrayWithRange:NSMakeRange(loc, len)];
        
        // 每批延迟0.1秒执行
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.1 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @synchronized(g_origImpMap) {
                for (DHScannerResult *r in batch) {
                    if ([r.methodName isEqualToString:@"(class)"]) continue;
                    Class cls = NSClassFromString(r.className);
                    if (!cls) continue;
                    if (r.isClassMethod) cls = object_getClass(cls);
                    SEL sel = NSSelectorFromString(r.methodName);
                    Method m = class_getInstanceMethod(cls, sel);
                    if (!m) continue;

                    NSString *key = [NSString stringWithFormat:@"%@|%@", r.className, r.methodName];
                    if (g_origImpMap[key]) continue;
                    IMP origImp = method_getImplementation(m);
                    g_origImpMap[key] = [NSValue valueWithPointer:origImp];
                    method_setImplementation(m, (IMP)dh_log_imp);
                }
            }
            if (i == batches - 1) {
                DHLogInfo(@"动态监控已启动，hook了%lu个方法", (unsigned long)g_origImpMap.count);
            }
        });
    }
}

- (void)stop {
    if (!g_monitoring) return;
    g_monitoring = NO;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @synchronized(g_origImpMap) {
            for (NSString *key in g_origImpMap.allKeys) {
                NSArray *parts = [key componentsSeparatedByString:@"|"];
                if (parts.count != 2) continue;
                Class cls = NSClassFromString(parts[0]);
                if (!cls) continue;
                SEL sel = NSSelectorFromString(parts[1]);
                Method m = class_getInstanceMethod(cls, sel);
                if (m) method_setImplementation(m, [g_origImpMap[key] pointerValue]);
            }
            [g_origImpMap removeAllObjects];
            [g_lastHitTime removeAllObjects];
        }
        DHLogInfo(@"动态监控已停止");
    });
}

- (void)clearEvents {
    dispatch_async(g_eventsQueue, ^{
        [g_eventsCache removeAllObjects];
        g_cacheCount = 0;
        [[NSFileManager defaultManager] removeItemAtPath:[self eventsFilePath] error:nil];
    });
}

#pragma mark - 页面追踪

- (BOOL)isTracking { return g_tracking; }

+ (UIViewController *)dhRealVC:(UIViewController *)vc {
    while ([vc isKindOfClass:[UINavigationController class]]) vc = [(UINavigationController *)vc visibleViewController];
    return vc;
}

+ (BOOL)dhIsPluginVC:(UIViewController *)vc {
    vc = [self dhRealVC:vc];
    NSString *cn = NSStringFromClass([vc class]);
    return [cn hasPrefix:@"DH"];
}

+ (UIViewController *)dhTopmostViewController {
    UIWindow *win = nil;
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *sc in [UIApplication sharedApplication].connectedScenes) {
            if (sc.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *w in sc.windows) {
                    if (!w.hidden && w.windowLevel == UIWindowLevelNormal) { win = w; break; }
                }
            }
            if (win) break;
        }
    }
    if (!win) win = [UIApplication sharedApplication].keyWindow;

    // 沿 presented 链走，记录最后一个「非本插件」的 App VC，跳过调试菜单自身
    UIViewController *vc = win.rootViewController;
    UIViewController *lastAppVC = nil;
    while (vc) {
        if (![self dhIsPluginVC:vc]) lastAppVC = vc;
        if (vc.presentedViewController) {
            vc = vc.presentedViewController;
        } else {
            break;
        }
    }
    UIViewController *result = [self dhRealVC:(lastAppVC ?: win.rootViewController)];
    return result;
}

- (void)trackClassMethods:(Class)cls {
    if (!cls) return;
    g_tracking = YES;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count); // 只返回 cls 自身声明的方法，不含父类
    @synchronized(g_origImpMap) {
        for (unsigned int i = 0; i < count; i++) {
            Method m = methods[i];
            SEL sel = method_getName(m);
            NSString *key = [NSString stringWithFormat:@"%@|%@", NSStringFromClass(cls), NSStringFromSelector(sel)];
            if (g_origImpMap[key]) continue;
            IMP orig = method_getImplementation(m);
            g_origImpMap[key] = [NSValue valueWithPointer:orig];
            [g_trackedKeys addObject:key];
            method_setImplementation(m, (IMP)dh_log_imp);
        }
    }
    if (methods) free(methods);
}

- (void)stopTracking {
    g_tracking = NO;
    @synchronized(g_origImpMap) {
        for (NSString *key in [g_trackedKeys copy]) {
            NSArray *parts = [key componentsSeparatedByString:@"|"];
            if (parts.count != 2) continue;
            Class cls = NSClassFromString(parts[0]);
            if (!cls) continue;
            SEL sel = NSSelectorFromString(parts[1]);
            Method m = class_getInstanceMethod(cls, sel);
            if (m) method_setImplementation(m, [g_origImpMap[key] pointerValue]);
            [g_origImpMap removeObjectForKey:key];
        }
        [g_trackedKeys removeAllObjects];
    }
}

@end
