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

#pragma mark - 页面追踪：只追踪指定 VC 类自身实现的方法
/// 取当前最顶层可见的视图控制器
+ (UIViewController *)dhTopmostViewController;
/// 只 swizzle 该类自己实现的实例方法（不碰父类），调用即记录
- (void)trackClassMethods:(Class)cls;
/// 停止页面追踪，只恢复本次追踪的方法
- (void)stopTracking;
/// 当前是否处于页面追踪
@property (nonatomic, assign, readonly) BOOL isTracking;
@end
