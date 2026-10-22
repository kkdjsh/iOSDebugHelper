//
//  DHAIManager.h
//  iOSDebugHelper
//  AI 辅助分析：对接 DeepSeek Chat Completions API
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DHAIConfig : NSObject <NSSecureCoding>
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *apiURL;     // 默认 https://api.deepseek.com/chat/completions
@property (nonatomic, copy) NSString *model;      // 默认 deepseek-chat
@end

@interface DHAIResult : NSObject
@property (nonatomic, copy) NSString *report;       // Markdown 分析报告
@property (nonatomic, copy) NSString *logosCode;    // 生成的 Logos 代码
@property (nonatomic, copy) NSArray<NSDictionary *> *suggestedHooks; // 建议 Hook 列表
@end

@interface DHAIManager : NSObject

@property (nonatomic, strong) DHAIConfig *config;

+ (instancetype)sharedManager;

/// 将类/方法信息提交给 AI 分析
/// @param classInfo 类信息描述文本
/// @param completion 完成回调
- (void)analyzeClassInfo:(NSString *)classInfo
              completion:(void(^)(DHAIResult * _Nullable result, NSError * _Nullable error))completion;

/// 保存配置到 NSUserDefaults
- (void)saveConfig;
- (void)loadConfig;

#pragma mark - 翻译缓存（内存字典 + 串行队列，周期落盘）
/// 纯内存查表，key 只用方法名
+ (nullable NSString *)translationForKey:(NSString *)key;
/// 只写内存，O(1)，不落盘；nil 表示删除
+ (void)setTranslation:(nullable NSString *)zh forKey:(NSString *)key;
/// 把内存缓存异步落盘为二进制 plist
+ (void)flushCache;
/// 合并导入字典到内存并同步落盘，返回合并后总条数
+ (NSUInteger)mergeTranslations:(NSDictionary<NSString *, NSString *> *)dict;
/// 返回内存缓存的不可变快照
+ (NSDictionary<NSString *, NSString *> *)snapshotTranslations;

@end

NS_ASSUME_NONNULL_END
