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
@end

@implementation DHMonitorManager

+ (instancetype)shared {
    static DHMonitorManager *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [self new];
        g_origImpMap = [NSMutableDictionary new];
        g_lastHitTime = [NSMutableDictionary new];
        g_events = [NSMutableArray new];
    });
    return s;
}

- (BOOL)isMonitoring { return g_monitoring; }
- (NSArray<DHMonitorEvent *> *)events { return [g_events copy]; }

// 通用日志IMP：根据typeEncoding安全处理
static void dh_log_imp(id self, SEL _cmd, ...) {
    NSString *clsName = NSStringFromClass([self class]);
    NSString *selName = NSStringFromSelector(_cmd);
    NSString *key = [NSString stringWithFormat:@"%@|%@", clsName, selName];

    // 防刷屏：1秒内同key只记一次
    @synchronized(g_lastHitTime) {
        NSDate *last = g_lastHitTime[key];
        NSDate *now = [NSDate date];
        if (last && [now timeIntervalSinceDate:last] < 1.0) return;
        g_lastHitTime[key] = now;
    }

    // 调原方法拿返回值（基本类型安全处理）
    Method m = class_getInstanceMethod([self class], _cmd);
    const char *retType = method_copyReturnType(m);
    NSString *retStr = @"";

    if (retType && (retType[0] == 'v')) {
        // void：直接调原方法
        IMP orig = [g_origImpMap[key] pointerValue];
        ((void(*)(id, SEL))orig)(self, _cmd);
        retStr = @"(void)";
    } else if (retType && (retType[0] == 'B' || retType[0] == 'c')) {
        // BOOL
        IMP orig = [g_origImpMap[key] pointerValue];
        BOOL (*origFn)(id, SEL) = (BOOL(*)(id, SEL))orig;
        BOOL result = origFn(self, _cmd);
        retStr = result ? @"YES" : @"NO";
    } else {
        // 其他类型：只调用不打印返回值
        IMP orig = [g_origImpMap[key] pointerValue];
        ((void(*)(id, SEL))orig)(self, _cmd);
        retStr = @"(non-bool)";
    }
    free((void *)retType);

    // 后台记录事件
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *stack = [NSThread callStackSymbols];
        NSMutableArray *filtered = [NSMutableArray new];
        NSString *appName = [[NSBundle mainBundle] infoDictionary][@"CFBundleExecutable"] ?: @"";
        for (NSString *line in stack) {
            if (line.length < 20) continue;
            // 过滤系统库，保留主App和SDK
            if ([line containsString:@"/System/Library/"] || [line containsString:@"libobjc"] ||
                [line containsString:@"libdyld"] || [line containsString:@"CoreFoundation"]) continue;
            if ([line containsString:appName] || [line containsString:@"GoogleMobileAds"] ||
                [line containsString:@"GDT"] || [line containsString:@"BUAd"]) {
                [filtered addObject:line];
            }
        }
        DHMonitorEvent *e = [DHMonitorEvent new];
        e.signature = [NSString stringWithFormat:@"%@ [%@]", selName, clsName];
        e.returnValue = retStr;
        e.callStack = [filtered componentsJoinedByString:@"\n"];
        e.time = [NSDate date];
        @synchronized(g_events) {
            [g_events addObject:e];
            if (g_events.count > 500) [g_events removeObjectsInRange:NSMakeRange(0, g_events.count - 500)];
        }
    });
}

- (void)startWithKeywords:(NSSet<NSString *> *)keywords {
    if (g_monitoring) return;
    g_monitoring = YES;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @synchronized(g_origImpMap) {
            unsigned int classCount;
            Class *classes = objc_copyClassList(&classCount);
            for (unsigned int i = 0; i < classCount; i++) {
                Class cls = classes[i];
                NSString *clsName = NSStringFromClass(cls);
                // 只扫非系统类
                if ([clsName hasPrefix:@"NS"] || [clsName hasPrefix:@"UI"] ||
                    [clsName hasPrefix:@"_"] || [clsName hasPrefix:@"__"]) continue;

                unsigned int methodCount;
                Method *methods = class_copyMethodList(cls, &methodCount);
                for (unsigned int j = 0; j < methodCount; j++) {
                    SEL sel = method_getName(methods[j]);
                    NSString *selName = NSStringFromSelector(sel);
                    // 检查是否命中关键词
                    BOOL hit = NO;
                    for (NSString *kw in keywords) {
                        if ([clsName rangeOfString:kw options:NSCaseInsensitiveSearch].location != NSNotFound ||
                            [selName rangeOfString:kw options:NSCaseInsensitiveSearch].location != NSNotFound) {
                            hit = YES; break;
                        }
                    }
                    if (!hit) continue;

                    NSString *key = [NSString stringWithFormat:@"%@|%@", clsName, selName];
                    if (g_origImpMap[key]) continue; // 已hook

                    IMP origImp = method_getImplementation(methods[j]);
                    g_origImpMap[key] = [NSValue valueWithPointer:origImp];
                    IMP newImp = (IMP)dh_log_imp;
                    method_setImplementation(methods[j], newImp);
                }
                free(methods);
            }
            free(classes);
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
    @synchronized(g_events) { [g_events removeAllObjects]; }
}

@end
