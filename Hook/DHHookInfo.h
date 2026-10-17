//
//  DHHookInfo.h
//  iOSDebugHelper
//  Hook 信息模型
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DHHookReturnType) {
    DHHookReturnVoid       = 0,
    DHHookReturnTrue       = 1,
    DHHookReturnFalse      = 2,
    DHHookReturnNil        = 3,
    DHHookReturnZero       = 4,
    DHHookReturnCustomString = 5,
    DHHookReturnCustomNumber = 6,
    DHHookReturnCustomValue  = 7,
};

@interface DHHookInfo : NSObject <NSSecureCoding>
@property (nonatomic, copy)   NSString *className;
@property (nonatomic, copy)   NSString *selectorName;
@property (nonatomic, assign) BOOL isClassMethod;
@property (nonatomic, assign) DHHookReturnType returnType;
@property (nonatomic, copy, nullable) id customValue;
@property (nonatomic, copy)   NSString *reason;  // 用途说明
@end

NS_ASSUME_NONNULL_END
