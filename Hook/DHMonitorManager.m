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
static NSMutableArray *g_events;
static BOOL g_monitoring = NO;

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
    NSArray *arr = [NSArray arrayWithContentsOfFile:[self eventsFilePath]];
    NSMutableArray *result = [NSMutableArray new];
    for (NSDictionary *dict in arr) {
        [result addObject:[[DHMonitorEvent alloc] initWithDict:dict]];
    }
    return result;
}

- (void)saveEvents:(NSArray *)events {
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

    @try {
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
        // 从文件读事件
        NSMutableArray *events = [NSMutableArray arrayWithArray:[self events]];
        @synchronized(events) {
            // 去重：找有没有已经记录过这个方法
            DHMonitorEvent *existing = nil;
            for (DHMonitorEvent *e in events) {
                if ([e.signature isEqualToString:sig]) { existing = e; break; }
            }
            if (existing) {
                // 已存在，计数+1，更新返回值和时间
                existing.count += 1;
                existing.returnValue = retStr;
                existing.time = [NSDate date];
                if (filtered.count > 0) existing.callStack = [filtered componentsJoinedByString:@"\n"];
            } else {
                // 新方法，新增
                DHMonitorEvent *e = [DHMonitorEvent new];
                e.signature = sig;
                e.returnValue = retStr;
                e.callStack = [filtered componentsJoinedByString:@"\n"];
                e.time = [NSDate date];
                e.count = 1;
                [events addObject:e];
            }
            // 保存到文件
            [self saveEvents:events];
        }
    });
}

- (void)startWithResults:(NSArray<DHScannerResult *> *)results {
    if (g_monitoring) return;
    g_monitoring = YES;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @synchronized(g_origImpMap) {
            for (DHScannerResult *r in results) {
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
        DHLogInfo(@"动态监控已启动，hook了%lu个方法", (unsigned long)g_origImpMap.count);
    });
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
    [[NSFileManager defaultManager] removeItemAtPath:[self eventsFilePath] error:nil];
}

@end
