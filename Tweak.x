// Tweak.x — iOSDebugHelper 入口
// 基于 FLEX 二次开发的 iOS 调试助手

#import <UIKit/UIKit.h>
#import "DHLogManager.h"
#import "DHRuleManager.h"
#import "DHHookManager.h"
#import "DHCryptManager.h"
#import "DHButtonManager.h"

static void DHInitializeDebugHelper(void) {
    @autoreleasepool {
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

        DHLogInfo(@"iOSDebugHelper 初始化完成");
    }
}

%ctor {
    // 延迟到 App 启动后执行，确保 UIKit 就绪
    dispatch_async(dispatch_get_main_queue(), ^{
        DHInitializeDebugHelper();
    });
}
