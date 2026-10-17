//
//  DHCryptManager.m
//  iOSDebugHelper
//

#import "DHCryptManager.h"
#import "DHLogManager.h"
#import <CommonCrypto/CommonCrypto.h>
#import <substrate.h>
#import <dlfcn.h>

@implementation DHCapturedCryptOperation
@end

@implementation DHCryptManager

+ (instancetype)sharedManager {
    static DHCryptManager *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [self new]; });
    return m;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _operations = [NSMutableArray new];
    }
    return self;
}

#pragma mark - CCCrypt Hook 声明
// 原始 CCCrypt 函数指针
static CCCryptorStatus (*orig_CCCrypt)(CCOperation op, CCAlgorithm alg, CCOptions options,
    const void *key, size_t keyLength, const void *iv, const void *dataIn, size_t dataInLength,
    void *dataOut, size_t dataOutAvailable, size_t *dataOutMoved);

static CCCryptorStatus hook_CCCrypt(CCOperation op, CCAlgorithm alg, CCOptions options,
    const void *key, size_t keyLength, const void *iv, const void *dataIn, size_t dataInLength,
    void *dataOut, size_t dataOutAvailable, size_t *dataOutMoved) {

    CCCryptorStatus result = orig_CCCrypt(op, alg, options, key, keyLength, iv,
                                          dataIn, dataInLength, dataOut, dataOutAvailable, dataOutMoved);

    if (alg == kCCAlgorithmAES && keyLength == kCCKeySizeAES128) {
        DHCapturedCryptOperation *capturedOp = [DHCapturedCryptOperation new];
        capturedOp.algorithm = (options & kCCOptionECBMode) ? @"AES-ECB" : @"AES-CBC";
        capturedOp.operation = (op == kCCEncrypt) ? @"ENCRYPT" : @"DECRYPT";
        capturedOp.key = [NSData dataWithBytes:key length:keyLength];
        capturedOp.iv = iv ? [NSData dataWithBytes:iv length:16] : nil;
        capturedOp.inputData = [NSData dataWithBytes:dataIn length:dataInLength];
        if (dataOutMoved) capturedOp.outputData = [NSData dataWithBytes:dataOut length:*dataOutMoved];
        capturedOp.threadID = [NSString stringWithFormat:@"%x", mach_task_self()];
        capturedOp.timestamp = [[NSDate date] timeIntervalSince1970];
        [[DHCryptManager sharedManager] recordOperation:capturedOp];
    }
    return result;
}

- (void)startMonitoring {
    // Hook CCCrypt
    MSHookFunction((void *)&CCCrypt, (void *)&hook_CCCrypt, (void **)&orig_CCCrypt);
    DHLogInfo(@"AES加密监控已启动 (CCCrypt hooked)");

    // Hook BoringSSL AES_encrypt
    void *boring = dlopen("/usr/lib/libboringssl.dylib", RTLD_NOW);
    if (boring) {
        DHLogInfo(@"已加载 BoringSSL 加密库");
    }
}

- (void)recordOperation:(DHCapturedCryptOperation *)op {
    @synchronized (self.operations) {
        [self.operations addObject:op];
    }
    DHLogDebug(@"捕获AES %@: Key=%lu bytes, IV=%@, Input=%lu bytes",
               op.operation, (unsigned long)op.key.length,
               op.iv ? @"有" : @"无", (unsigned long)op.inputData.length);
}

- (NSData *)decryptData:(NSData *)data forThreadID:(NSString *)threadID {
    // 查找最近的 DECRYPT 操作匹配
    @synchronized (self.operations) {
        for (DHCapturedCryptOperation *op in [self.operations reverseObjectEnumerator]) {
            if ([op.operation isEqualToString:@"DECRYPT"] && op.key) {
                // 使用捕获的 Key+IV 尝试解密
                NSMutableData *result = [NSMutableData dataWithLength:data.length + kCCBlockSizeAES128];
                size_t outMoved;
                CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                        op.key.bytes, op.key.length, op.iv.bytes,
                        data.bytes, data.length, result.mutableBytes, result.length, &outMoved);
                result.length = outMoved;
                DHLogInfo(@"已关联解密: 使用 %@ 密钥解密 %lu bytes", op.algorithm, (unsigned long)data.length);
                return result;
            }
        }
    }
    return nil;
}

- (void)clearAll {
    @synchronized (self.operations) {
        [self.operations removeAllObjects];
    }
}

@end
