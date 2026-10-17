//
//  DHLogManager.m
//  iOSDebugHelper
//

#import "DHLogManager.h"

static DHLogLevel _logLevel = DHLogLevelInfo;

@implementation DHLogManager

+ (instancetype)sharedManager {
    static DHLogManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

+ (void)setLogLevel:(DHLogLevel)level {
    _logLevel = level;
}

- (void)setLogLevel:(DHLogLevel)logLevel {
    _logLevel = logLevel;
}

- (DHLogLevel)logLevel {
    return _logLevel;
}

- (NSString *)logsDirectory {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [docs stringByAppendingPathComponent:@"iOSDebugHelper_Logs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

- (NSString *)currentLogFilePath {
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateFormat = @"yyyyMMdd";
    NSString *name = [NSString stringWithFormat:@"DebugHelper_%@.log", [fmt stringFromDate:[NSDate date]]];
    return [[self logsDirectory] stringByAppendingPathComponent:name];
}

- (void)log:(DHLogLevel)level format:(NSString *)format, ... {
    if (level < _logLevel) return;

    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSString *levelStr;
    switch (level) {
        case DHLogLevelDebug: levelStr = @"DEBUG"; break;
        case DHLogLevelInfo:  levelStr = @"INFO";  break;
        case DHLogLevelWarn:  levelStr = @"WARN";  break;
        case DHLogLevelError: levelStr = @"ERROR"; break;
    }

    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *timestamp = [fmt stringFromDate:[NSDate date]];
    NSString *line = [NSString stringWithFormat:@"[%@] [%@] %@\n", timestamp, levelStr, message];

    // 写入文件
    NSString *path = [self currentLogFilePath];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } else {
        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }

    // 同时输出到控制台
    NSLog(@"%@", line);
}

- (NSString *)readTodayLog {
    NSString *path = [self currentLogFilePath];
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
}

- (void)clearTodayLog {
    [[NSFileManager defaultManager] removeItemAtPath:[self currentLogFilePath] error:nil];
}

@end
