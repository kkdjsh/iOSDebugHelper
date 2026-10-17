//
//  DHAdScanner.h
//  iOSDebugHelper
//  智能广告 & VIP 扫描器：扫描 ObjC 类与方法，分类标记
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DHScannerCategory) {
    DHScannerCategoryAd       = 0,  // 广告相关
    DHScannerCategoryVIP      = 1,  // VIP/会员/付费相关
    DHScannerCategorySuspicious = 2, // 其他可疑类
};

@interface DHScannerResult : NSObject
@property (nonatomic, copy)   NSString *methodName;
@property (nonatomic, copy)   NSString *className;
@property (nonatomic, assign) DHScannerCategory category;
@property (nonatomic, copy)   NSString *matchedKeyword;
@property (nonatomic, copy)   NSString *returnType;      // 如 BOOL, void, id
@property (nonatomic, copy)   NSString *imageName;      // 所属动态库
@property (nonatomic, assign) BOOL isClassMethod;
@end

@interface DHAdScanner : NSObject

/// 内置关键词词库
@property (nonatomic, copy) NSArray<NSString *> *adKeywords;      // 广告类
@property (nonatomic, copy) NSArray<NSString *> *vipKeywords;     // VIP/付费类
@property (nonatomic, copy) NSArray<NSString *> *customKeywords;  // 用户自定义

+ (instancetype)sharedScanner;

/// 全局扫描：遍历已加载的 ObjC 类和方法（全量dump）
- (void)scanAllClassesWithProgress:(void(^)(NSUInteger current, NSUInteger total))progress
                         completion:(void(^)(NSArray<DHScannerResult *> *results))completion;

/// 智能扫描：只匹配VIP/广告/付费相关关键词
- (void)scanSmartWithProgress:(void(^)(NSUInteger current, NSUInteger total))progress
                   completion:(void(^)(NSArray<DHScannerResult *> *results))completion;

/// 批量复制前 N 条结果到剪贴板
/// @param count 前N条
/// @param results 全部结果
/// @return 拼接后的文本
- (NSString *)batchCopyTopN:(NSInteger)count results:(NSArray<DHScannerResult *> *)results;

@end

NS_ASSUME_NONNULL_END
