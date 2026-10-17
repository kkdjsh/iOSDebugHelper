//
//  DHInterceptRule.h
//  iOSDebugHelper
//  网络拦截规则模型
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DHMatchType) {
    DHMatchTypeContains = 0,
    DHMatchTypeRegex    = 1,
};

@interface DHJSONPatchItem : NSObject <NSSecureCoding>
@property (nonatomic, copy) NSString *keyPath;   // e.g. data.user.isVip
@property (nonatomic, copy) NSString *valueString; // e.g. true, 123, "text"
@end

@interface DHHeaderOverride : NSObject <NSSecureCoding>
@property (nonatomic, copy) NSString *headerName;
@property (nonatomic, copy) NSString *headerValue;
@end

@interface DHInterceptRule : NSObject <NSSecureCoding>
@property (nonatomic, copy)   NSString *urlPattern;
@property (nonatomic, assign) DHMatchType matchType;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, copy)   NSArray<DHJSONPatchItem *> *patches;
@property (nonatomic, copy)   NSArray<DHHeaderOverride *> *requestHeaderOverrides;
@property (nonatomic, assign) BOOL applyCookieToStorage;

- (BOOL)matchesURL:(NSString *)url;
- (nullable id)applyPatchesToJSON:(id)jsonObject;
@end

NS_ASSUME_NONNULL_END
