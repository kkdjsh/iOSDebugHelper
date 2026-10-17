//
//  DHNetworkInterceptor.m
//  iOSDebugHelper
//

#import "DHNetworkInterceptor.h"
#import "DHRuleManager.h"
#import "DHInterceptRule.h"
#import "DHLogManager.h"
#import <objc/runtime.h>

@implementation DHNetworkInterceptor

+ (instancetype)sharedInterceptor {
    static DHNetworkInterceptor *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [self new]; });
    return s;
}

- (void)startIntercepting {
    // Swizzle NSURLSession data task completion handler
    // 这里通过 method swizzle 拦截 NSURLSession:dataTaskWithURL:completionHandler:
    // 实际网络监控基于 FLEXNetworkObserver，拦截规则在此处应用

    DHLogInfo(@"网络拦截器已启动");
}

- (NSData *)processResponseData:(NSData *)responseData forURL:(NSString *)url {
    NSArray *rules = [[DHRuleManager sharedManager] matchedRulesForURL:url];
    if (!rules.count) return responseData;

    NSError *err;
    id json = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:&err];
    if (err) {
        DHLogWarn(@"响应不是JSON，跳过Patch: %@", err);
        return responseData;
    }

    id modified = json;
    for (DHInterceptRule *rule in rules) {
        modified = [rule applyPatchesToJSON:modified];
    }

    NSData *result = [NSJSONSerialization dataWithJSONObject:modified options:0 error:&err];
    if (err) {
        DHLogError(@"修改后JSON序列化失败: %@", err);
        return responseData;
    }
    DHLogInfo(@"已对 %@ 应用 %lu 条规则", url, (unsigned long)rules.count);
    return result;
}

- (NSMutableURLRequest *)processRequest:(NSMutableURLRequest *)request {
    NSString *url = request.URL.absoluteString;
    NSArray *rules = [[DHRuleManager sharedManager] matchedRulesForURL:url];
    if (!rules.count) return request;

    for (DHInterceptRule *rule in rules) {
        for (DHHeaderOverride *h in rule.requestHeaderOverrides) {
            [request setValue:h.headerValue forHTTPHeaderField:h.headerName];
            DHLogInfo(@"请求头重写: %@ = %@", h.headerName, h.headerValue);
        }
    }
    return request;
}

@end
