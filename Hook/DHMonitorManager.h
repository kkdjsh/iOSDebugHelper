//
//  DHMonitorManager.h
//  iOSDebugHelper
//  动态监控：基于词库批量Swizzle记录方法调用
//

#import <Foundation/Foundation.h>

@interface DHMonitorEvent : NSObject
@property (nonatomic, copy) NSString *signature;
@property (nonatomic, copy) NSString *returnValue;
@property (nonatomic, copy) NSString *callStack;
@property (nonatomic, copy) NSDate *time;
@end

@interface DHMonitorManager : NSObject
+ (instancetype)shared;
@property (nonatomic, assign, readonly) BOOL isMonitoring;
@property (nonatomic, copy, readonly) NSArray<DHMonitorEvent *> *events;
- (void)startWithKeywords:(NSSet<NSString *> *)keywords;
- (void)stop;
- (void)clearEvents;
@end
