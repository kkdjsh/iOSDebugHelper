//
//  DHPatch.h
//  iOSDebugHelper
//  补丁模型：包含多个 Hook + 网络规则
//

#import <Foundation/Foundation.h>
#import "DHHookInfo.h"
#import "DHInterceptRule.h"

NS_ASSUME_NONNULL_BEGIN

@interface DHPatch : NSObject <NSSecureCoding>
@property (nonatomic, copy) NSString *patchName;
@property (nonatomic, copy) NSArray<DHHookInfo *> *hooks;
@property (nonatomic, copy) NSArray<DHInterceptRule *> *rules;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, copy) NSDate *createdAt;
@end

NS_ASSUME_NONNULL_END
