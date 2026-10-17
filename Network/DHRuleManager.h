//
//  DHRuleManager.h
//  iOSDebugHelper
//  网络拦截规则管理器，持久化到 NSUserDefaults
//

#import <Foundation/Foundation.h>
#import "DHInterceptRule.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const kDHRulesDefaultsKey  = @"DHInterceptRules";
static NSString *const kDHInterceptEnabledKey = @"DHInterceptEnabled";

@interface DHRuleManager : NSObject

@property (nonatomic, copy) NSArray<DHInterceptRule *> *rules;
@property (nonatomic, assign) BOOL globalEnabled;

+ (instancetype)sharedManager;

- (void)loadRules;
- (void)saveRules;

/// 返回匹配 URL 的启用规则
- (NSArray<DHInterceptRule *> *)matchedRulesForURL:(NSString *)url;

/// 添加默认规则：/api/User/Info → result.isVip = true
- (void)addDefaultRuleIfNeeded;

@end

NS_ASSUME_NONNULL_END
