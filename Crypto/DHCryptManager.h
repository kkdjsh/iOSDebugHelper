//
//  DHCryptManager.h
//  iOSDebugHelper
//  AES 加密监控：Hook CommonCrypto/OpenSSL/CryptoKit，捕获 Key+IV，关联网络请求
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DHCapturedCryptOperation : NSObject
@property (nonatomic, copy)   NSString *algorithm;    // AES-CBC / AES-ECB / AES-GCM
@property (nonatomic, copy)   NSString *operation;   // ENCRYPT / DECRYPT
@property (nonatomic, strong) NSData *key;
@property (nonatomic, strong, nullable) NSData *iv;
@property (nonatomic, strong) NSData *inputData;
@property (nonatomic, strong) NSData *outputData;
@property (nonatomic, copy)   NSString *threadID;
@property (nonatomic, assign) NSTimeInterval timestamp;
@end

@interface DHCryptManager : NSObject

@property (nonatomic, copy) NSMutableArray<DHCapturedCryptOperation *> *operations;

+ (instancetype)sharedManager;

/// 启动加密监控，Hook 所有 AES 相关函数
- (void)startMonitoring;

/// 记录一次加密操作
- (void)recordOperation:(DHCapturedCryptOperation *)op;

/// 根据线程ID和时间查找匹配的网络请求并解密响应
- (nullable NSData *)decryptData:(NSData *)data forThreadID:(NSString *)threadID;

/// 清除所有记录
- (void)clearAll;

@end

NS_ASSUME_NONNULL_END
