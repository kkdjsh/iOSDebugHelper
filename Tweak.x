// Tweak.x — iOSDebugHelper 入口
// 基于 FLEX 二次开发的 iOS 调试助手

#import <UIKit/UIKit.h>
#import <signal.h>
#import "DHLogManager.h"
#import "DHRuleManager.h"
#import "DHHookManager.h"
#import "DHCryptManager.h"
#import "DHButtonManager.h"
#import "DHAdScanner.h"
#import "DHBuiltinKeywords.h"

// 全局崩溃捕获：把异常/信号写到 Documents/iOSDebugHelper/crash.log，便于定位闪退
static void dh_writeCrash(NSString *txt) {
    @try {
        NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *folder = [dir stringByAppendingPathComponent:@"iOSDebugHelper"];
        [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *log = [folder stringByAppendingPathComponent:@"crash.log"];
        NSString *old = [NSString stringWithContentsOfFile:log encoding:NSUTF8StringEncoding error:nil] ?: @"";
        [[old stringByAppendingString:txt] writeToFile:log atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch (NSException *e) {}
}

static void dh_uncaughtException(NSException *e) {
    dh_writeCrash([NSString stringWithFormat:@"\n=== EXCEPTION %@ ===\n%@\n%@\n", e.name, e.reason, e.callStackSymbols]);
}

static void dh_signalHandler(int sig) {
    dh_writeCrash([NSString stringWithFormat:@"\n=== SIGNAL %d (%s) ===\n", sig, strsignal(sig)]);
    signal(sig, SIG_DFL);
    raise(sig);
}

static void dh_installCrashHandler(void) {
    NSSetUncaughtExceptionHandler(&dh_uncaughtException);
    signal(SIGSEGV, dh_signalHandler);
    signal(SIGABRT, dh_signalHandler);
    signal(SIGBUS, dh_signalHandler);
    signal(SIGILL, dh_signalHandler);
    signal(SIGFPE, dh_signalHandler);
}

static void DHInitializeDebugHelper(void) {
    @autoreleasepool {
        [DHBuiltinKeywords ensureSeeded];
        [DHLogManager sharedManager].logLevel = DHLogLevelDebug;
        DHLogInfo(@"iOSDebugHelper v1.0.0 启动中...");

        // 1. 加载并应用持久化的 Hook 配置
        [[DHHookManager sharedManager] applyEnabledHooks];

        // 2. 初始化网络拦截规则
        [[DHRuleManager sharedManager] loadRules];

        // 3. 启动 AES 加密监控
        [[DHCryptManager sharedManager] startMonitoring];

        // 4. 显示悬浮球入口
        [[DHButtonManager sharedManager] showFloatingButton];

        // 5. 启动时自动后台扫描，缓存结果
        [[DHAdScanner sharedScanner] scanAllClassesWithProgress:nil completion:^(NSArray<DHScannerResult *> *results) {
            [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:results] forKey:@"DHScanCache"];
            DHLogInfo(@"自动扫描完成: %lu 条结果已缓存", (unsigned long)results.count);
        }];

        DHLogInfo(@"iOSDebugHelper 初始化完成");
    }
}

%ctor {
    dh_installCrashHandler();
    // 延迟到 App 启动后执行，确保 UIKit 就绪
    dispatch_async(dispatch_get_main_queue(), ^{
        DHInitializeDebugHelper();
    });
}
