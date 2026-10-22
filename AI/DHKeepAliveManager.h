#import <Foundation/Foundation.h>

// 无声音频保活：激活 Playback 音频会话并循环播放静音，让进程在后台不被挂起
@interface DHKeepAliveManager : NSObject

+ (instancetype)shared;

// 开始静音循环播放（后台保活）
- (void)startSilentLoop;
// 停止静音播放并释放会话
- (void)stopSilent;

@end
