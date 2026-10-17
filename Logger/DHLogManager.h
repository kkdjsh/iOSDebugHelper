//
//  DHLogManager.h
//  iOSDebugHelper
//  分级日志管理，持久化到 Documents 目录
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DHLogLevel) {
    DHLogLevelDebug = 0,
    DHLogLevelInfo  = 1,
    DHLogLevelWarn  = 2,
    DHLogLevelError = 3,
};

#define DHLogDebug(fmt, ...) [[DHLogManager sharedManager] log:DHLogLevelDebug format:(fmt), ##__VA_ARGS__]
#define DHLogInfo(fmt, ...)  [[DHLogManager sharedManager] log:DHLogLevelInfo  format:(fmt), ##__VA_ARGS__]
#define DHLogWarn(fmt, ...)  [[DHLogManager sharedManager] log:DHLogLevelWarn  format:(fmt), ##__VA_ARGS__]
#define DHLogError(fmt, ...) [[DHLogManager sharedManager] log:DHLogLevelError format:(fmt), ##__VA_ARGS__]

@interface DHLogManager : NSObject

@property (nonatomic, assign) DHLogLevel logLevel;

+ (instancetype)sharedManager;

- (void)log:(DHLogLevel)level format:(NSString *)format, ... NS_FORMAT_FUNCTION(2, 3);

/// 读取当日日志内容
- (NSString *)readTodayLog;

/// 清空当日日志
- (void)clearTodayLog;

/// 日志文件路径
- (NSString *)currentLogFilePath;

@end

NS_ASSUME_NONNULL_END
