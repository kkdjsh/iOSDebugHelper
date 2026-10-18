//
//  DHHookManager.h
//  iOSDebugHelper
//  Hook 管理器：运行时 Hook OC 方法，持久化到 NSUserDefaults
//

#import <Foundation/Foundation.h>
#import "DHHookInfo.h"
#import "DHPatch.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const kDHSavedHooksKey  = @"DHSavedHooks";
static NSString *const kDHSavedPatchesKey = @"DHSavedPatches";

@interface DHHookManager : NSObject

@property (nonatomic, copy) NSArray<DHHookInfo *> *savedHooks;
@property (nonatomic, copy) NSArray<DHPatch *> *savedPatches;

+ (instancetype)sharedManager;

/// 启动时加载并应用所有已保存的 Hook
- (void)applyEnabledHooks;

/// 添加一个 Hook 并持久化
- (void)addHook:(DHHookInfo *)hook;

/// 移除 Hook
- (void)removeHook:(DHHookInfo *)hook;

/// 切换 Hook 启用/禁用
- (void)toggleHook:(DHHookInfo *)hook;

/// 立即应用单个Hook
- (void)applyHook:(DHHookInfo *)hook;

/// 保存配置到 NSUserDefaults
- (void)saveHooks;

/// 清除所有已保存的 Hook
- (void)clearAllHooks;

/// 导出 Hook 配置为 Logos Tweak.x 代码
- (NSString *)exportLogosCode;

@end

NS_ASSUME_NONNULL_END
