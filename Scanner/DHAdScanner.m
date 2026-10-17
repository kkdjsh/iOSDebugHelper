//
//  DHAdScanner.m
//  iOSDebugHelper
//

#import "DHAdScanner.h"
#import "DHLogManager.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@implementation DHAdScanner

+ (instancetype)sharedScanner {
    static DHAdScanner *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [self new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _adKeywords = @[@"Ad", @"Advertisement", @"Banner", @"Interstitial", @"Rewarded",
                        @"Splash", @"Popup", @"GAD", @"GADRequest", @"GADBannerView",
                        @"FBAd", @"AdMob", @"AdView", @"AdCell", @"AdLoader",
                        @"showAd", @"loadAd", @"closeAd", @"skipAd"];
        _vipKeywords = @[@"Vip", @"VIP", @"Premium", @"Member", @"Membership",
                         @"Purchase", @"Pay", @"Subscribe", @"Subscription", @"Trial",
                         @"Unlock", @"IsVip", @"isVip",
                         @"hasPermission", @"unlock", @"restriction",
                         @"Receipt", @"IAP", @"StoreKit", @"productId"];
        _customKeywords = @[];
    }
    return self;
}

- (void)scanAllClassesWithProgress:(void(^)(NSUInteger, NSUInteger))progress
                        completion:(void(^)(NSArray<DHScannerResult *> *))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *results = [NSMutableArray new];
        unsigned int classCount;
        Class *classes = objc_copyClassList(&classCount);
        NSMutableArray *allKeywords = [NSMutableArray new];
        [allKeywords addObjectsFromArray:self.adKeywords];
        [allKeywords addObjectsFromArray:self.vipKeywords];
        [allKeywords addObjectsFromArray:self.customKeywords];

        for (unsigned int i = 0; i < classCount; i++) {
            @autoreleasepool {
                Class cls = classes[i];
                NSString *className = NSStringFromClass(cls);

                // 过滤掉系统框架类，只保留App自己的类
                if ([className hasPrefix:@"NS"] || [className hasPrefix:@"UI"] ||
                    [className hasPrefix:@"CA"] || [className hasPrefix:@"CF"] ||
                    [className hasPrefix:@"_NS"] || [className hasPrefix:@"__NS"] ||
                    [className hasPrefix:@"WK"] || [className hasPrefix:@"AV"] ||
                    [className hasPrefix:@"CK"] || [className hasPrefix:@"OS"] ||
                    [className hasPrefix:@"DF"] || [className hasPrefix:@"LS"] ||
                    [className hasPrefix:@"SL"] || [className hasPrefix:@"TL"] ||
                    [className hasPrefix:@"TU"] || [className hasPrefix:@"MT"] ||
                    [className containsString:@"Proxy"] || [className containsString:@"Weak"]) {
                    continue;
                }

                // 检查类名是否匹配关键词
                for (NSString *kw in allKeywords) {
                    if ([className localizedCaseInsensitiveContainsString:kw]) {
                        DHScannerResult *r = [DHScannerResult new];
                        r.methodName = @"(class)";
                        r.className = className;
                        r.matchedKeyword = kw;
                        if ([self.adKeywords containsObject:kw]) {
                            r.category = DHScannerCategoryAd;
                        } else if ([self.vipKeywords containsObject:kw]) {
                            r.category = DHScannerCategoryVIP;
                        } else {
                            r.category = DHScannerCategorySuspicious;
                        }
                        [results addObject:r];
                        break;
                    }
                }

                // 遍历实例方法
                unsigned int methodCount;
                Method *methods = class_copyMethodList(cls, &methodCount);
                for (unsigned int j = 0; j < methodCount; j++) {
                    SEL sel = method_getName(methods[j]);
                    NSString *selName = NSStringFromSelector(sel);
                    // 过滤掉NSObject boilerplate方法
                    if ([selName isEqualToString:@"isProxy"] ||
                        [selName isEqualToString:@"isMemberOfClass:"] ||
                        [selName isEqualToString:@"isKindOfClass:"] ||
                        [selName isEqualToString:@"conformsToProtocol:"] ||
                        [selName isEqualToString:@"respondsToSelector:"] ||
                        [selName isEqualToString:@"class"] ||
                        [selName isEqualToString:@"superclass"] ||
                        [selName isEqualToString:@"retain"] ||
                        [selName isEqualToString:@"release"] ||
                        [selName isEqualToString:@"autorelease"] ||
                        [selName isEqualToString:@"retainCount"] ||
                        [selName isEqualToString:@"description"] ||
                        [selName isEqualToString:@"debugDescription"]) {
                        continue;
                    }
                    for (NSString *kw in allKeywords) {
                        if ([selName localizedCaseInsensitiveContainsString:kw]) {
                            DHScannerResult *r = [DHScannerResult new];
                            r.methodName = selName;
                            r.className = className;
                            r.matchedKeyword = kw;
                            if ([self.adKeywords containsObject:kw]) {
                                r.category = DHScannerCategoryAd;
                            } else if ([self.vipKeywords containsObject:kw]) {
                                r.category = DHScannerCategoryVIP;
                            } else {
                                r.category = DHScannerCategorySuspicious;
                            }
                            [results addObject:r];
                            break;
                        }
                    }
                }
                free(methods);

                if (progress && i % 100 == 0) progress(i, classCount);
            }
        }
        free(classes);

        DHLogInfo(@"扫描完成: 共 %u 个类, 命中 %lu 条结果", classCount, (unsigned long)results.count);
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(results);
        });
    });
}

- (NSString *)batchCopyTopN:(NSInteger)count results:(NSArray<DHScannerResult *> *)results {
    if (count <= 0 || results.count == 0) return @"";
    NSInteger n = MIN(count, (NSInteger)results.count);
    NSMutableArray *lines = [NSMutableArray new];
    for (NSInteger i = 0; i < n; i++) {
        DHScannerResult *r = results[i];
        [lines addObject:[NSString stringWithFormat:@"%@ In Class: %@", r.methodName, r.className]];
    }
    NSString *text = [lines componentsJoinedByString:@"\n"];
    UIPasteboard.generalPasteboard.string = text;
    DHLogInfo(@"批量复制 %ld 条结果到剪贴板", (long)n);
    return text;
}

@end
