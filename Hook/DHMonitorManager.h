//
//  DHMonitorManager.h
//  iOSDebugHelper
//  动态监控：基于词库批量Swizzle记录方法调用
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "DHAdScanner.h"

@interface DHMonitorEvent : NSObject
@property (nonatomic, copy) NSString *signature;
@property (nonatomic, copy) NSString *returnValue;
@property (nonatomic, copy) NSString *callStack;
@property (nonatomic, copy) NSDate *time;
@property (nonatomic, assign) NSInteger count;
@end

@interface DHMonitorManager : NSObject
+ (instancetype)shared;
@property (nonatomic, assign, readonly) BOOL isMonitoring;
@property (nonatomic, copy, readonly) NSArray<DHMonitorEvent *> *events;
- (void)startWithResults:(NSArray<DHScannerResult *> *)results;
- (void)stop;
- (void)clearEvents;
- (NSArray<NSString *> *)allMonitoredMethods;
@end
