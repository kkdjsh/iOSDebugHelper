//
//  DHRuleManager.m
//  iOSDebugHelper
//

#import "DHRuleManager.h"
#import "DHLogManager.h"

@implementation DHRuleManager

+ (instancetype)sharedManager {
    static DHRuleManager *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [self new]; });
    return m;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _rules = @[];
        _globalEnabled = YES;
    }
    return self;
}

- (void)loadRules {
    NSData *data = [[NSUserDefaults standardUserDefaults] dataForKey:kDHRulesDefaultsKey];
    if (!data) {
        DHLogInfo(@"未找到已保存规则，创建默认规则");
        [self addDefaultRuleIfNeeded];
        return;
    }
    NSError *err;
    NSArray *rules = [NSKeyedUnarchiver unarchivedArrayOfClassObjects:[DHInterceptRule class] fromData:data error:&err];
    if (err) {
        DHLogError(@"规则反序列化失败: %@", err);
        rules = @[];
    }
    self.rules = rules ?: @[];
    self.globalEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:kDHInterceptEnabledKey];
    DHLogInfo(@"已加载 %lu 条拦截规则", (unsigned long)self.rules.count);
}

- (void)saveRules {
    NSError *err;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.rules requiringSecureCoding:YES error:&err];
    if (err) {
        DHLogError(@"规则序列化失败: %@", err);
        return;
    }
    [[NSUserDefaults standardUserDefaults] setObject:data forKey:kDHRulesDefaultsKey];
    [[NSUserDefaults standardUserDefaults] setBool:self.globalEnabled forKey:kDHInterceptEnabledKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    DHLogInfo(@"规则已保存 (%lu 条, %lu bytes)", (unsigned long)self.rules.count, (unsigned long)data.length);
}

- (NSArray<DHInterceptRule *> *)matchedRulesForURL:(NSString *)url {
    if (!self.globalEnabled) return @[];
    NSMutableArray *result = [NSMutableArray new];
    for (DHInterceptRule *rule in self.rules) {
        if (!rule.enabled) continue;
        if ([rule matchesURL:url]) [result addObject:rule];
    }
    return result;
}

- (void)addDefaultRuleIfNeeded {
    DHJSONPatchItem *patch = [DHJSONPatchItem new];
    patch.keyPath = @"result.isVip";
    patch.valueString = @"true";

    DHInterceptRule *rule = [DHInterceptRule new];
    rule.urlPattern = @"/api/User/Info";
    rule.matchType = DHMatchTypeContains;
    rule.enabled = YES;
    rule.patches = @[patch];
    rule.requestHeaderOverrides = @[];

    self.rules = @[rule];
    [self saveRules];
    DHLogInfo(@"已创建默认规则: /api/User/Info → result.isVip=true");
}

@end
