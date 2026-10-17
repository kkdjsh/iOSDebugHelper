//
//  DHNetworkInterceptor.h
//  iOSDebugHelper
//  网络拦截器：Swizzle NSURLSession/NSURLConnection，应用规则
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DHNetworkInterceptor : NSObject

+ (instancetype)sharedInterceptor;

/// 启动网络拦截 Swizzle
- (void)startIntercepting;

/// 处理响应数据：匹配规则并修改响应体
- (NSData *)processResponseData:(NSData *)responseData forURL:(NSString *)url;

/// 处理请求：应用请求头重写
- (NSMutableURLRequest *)processRequest:(NSMutableURLRequest *)request;

@end

NS_ASSUME_NONNULL_END
