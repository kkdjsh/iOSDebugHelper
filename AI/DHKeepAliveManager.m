#import "DHKeepAliveManager.h"
#import <AVFoundation/AVFoundation.h>

@interface DHKeepAliveManager ()
@property (nonatomic, strong) AVAudioPlayer *player;
@end

@implementation DHKeepAliveManager

+ (instancetype)shared {
    static DHKeepAliveManager *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [DHKeepAliveManager new]; });
    return inst;
}

// 动态构造一段静音 WAV（PCM 8000Hz mono 16bit，约2秒），不依赖外部文件
- (NSData *)silentWavData {
    NSInteger sampleRate = 8000;
    NSInteger seconds = 2;
    NSInteger numSamples = sampleRate * seconds;
    NSInteger dataSize = numSamples * 2; // mono 16bit
    NSInteger chunkSize = 36 + dataSize;

    NSMutableData *d = [NSMutableData data];
    // RIFF header
    [d appendBytes:"RIFF" length:4];
    uint32_t v = (uint32_t)chunkSize;
    [d appendBytes:&v length:4];
    [d appendBytes:"WAVE" length:4];
    // fmt subchunk
    [d appendBytes:"fmt " length:4];
    v = 16; [d appendBytes:&v length:4];
    uint16_t fmt = 1; [d appendBytes:&fmt length:2];       // PCM
    uint16_t ch = 1; [d appendBytes:&ch length:2];        // mono
    v = (uint32_t)sampleRate; [d appendBytes:&v length:4];
    v = (uint32_t)(sampleRate * 2); [d appendBytes:&v length:4]; // byte rate
    fmt = 2; [d appendBytes:&fmt length:2];               // block align
    fmt = 16; [d appendBytes:&fmt length:2];              // bits per sample
    // data subchunk
    [d appendBytes:"data" length:4];
    v = (uint32_t)dataSize; [d appendBytes:&v length:4];
    // 全零静音样本
    NSMutableData *zero = [NSMutableData dataWithLength:dataSize];
    [d appendData:zero];
    return d;
}

- (void)startSilentLoop {
    @try {
        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setCategory:AVAudioSessionCategoryPlayback options:0 error:nil];
        [session setActive:YES error:nil];

        if (self.player && self.player.isPlaying) return;
        NSError *err = nil;
        self.player = [[AVAudioPlayer alloc] initWithData:[self silentWavData] error:&err];
        if (err || !self.player) return;
        self.player.numberOfLoops = -1; // 无限循环
        self.player.volume = 0;
        [self.player prepareToPlay];
        [self.player play];
    } @catch (NSException *e) {}
}

- (void)stopSilent {
    @try {
        [self.player stop];
        self.player = nil;
        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
    } @catch (NSException *e) {}
}

@end
