//
//  DHAdScanner.m
//  iOSDebugHelper
//  智能扫描(VIP/广告关键词) + 全局扫描(全量dump)
//

#import "DHAdScanner.h"
#import "DHLogManager.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString *DHReturnTypeEncoding(Method m) {
    const char *ret = method_copyReturnType(m);
    if (!ret) return @"id";
    NSString *s = [NSString stringWithUTF8String:ret];
    free((void *)ret);
    if ([s isEqualToString:@"v"]) return @"void";
    if ([s isEqualToString:@"B"] || [s isEqualToString:@"c"]) return @"BOOL";
    if ([s isEqualToString:@"C"]) return @"unsigned char";
    if ([s isEqualToString:@"i"] || [s isEqualToString:@"s"] || [s isEqualToString:@"l"] || [s isEqualToString:@"q"]) return @"NSInteger";
    if ([s isEqualToString:@"I"] || [s isEqualToString:@"L"] || [s isEqualToString:@"Q"]) return @"NSUInteger";
    if ([s isEqualToString:@"f"]) return @"float";
    if ([s isEqualToString:@"d"]) return @"double";
    if ([s isEqualToString:@"@"]) return @"id";
    if ([s isEqualToString:@"#"]) return @"Class";
    if ([s isEqualToString:@":"]) return @"SEL";
    return @"id";
}

static NSString *DHImageNameForClass(Class cls) {
    const char *name = class_getImageName(cls);
    if (!name) return @"";
    return [[NSString stringWithUTF8String:name] lastPathComponent];
}

static NSString *DHBuildFullSignature(Method m, BOOL isClass) {
    NSString *prefix = isClass ? @"+" : @"-";
    NSString *ret = DHReturnTypeEncoding(m);
    SEL sel = method_getName(m);
    NSString *selName = NSStringFromSelector(sel);
    NSUInteger argc = [[selName componentsSeparatedByString:@":"] count] - 1;
    if (argc == 0) {
        return [NSString stringWithFormat:@"%@ (%@)%@", prefix, ret, selName];
    }
    NSArray *parts = [selName componentsSeparatedByString:@":"];
    NSMutableString *sig = [NSMutableString stringWithFormat:@"%@ (%@)", prefix, ret];
    NSUInteger argIdx = 1;
    for (NSUInteger i = 0; i < parts.count; i++) {
        NSString *part = parts[i];
        if (part.length == 0) continue;
        if (argIdx == 1) [sig appendFormat:@"%@:(id)arg%lu", part, (unsigned long)argIdx];
        else [sig appendFormat:@" %@:(id)arg%lu", part, (unsigned long)argIdx];
        argIdx++;
    }
    return sig;
}

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
        // 智能扫描关键词库 - 精准匹配VIP/广告/付费相关
        _adKeywords = @[@"showAd", @"loadAd", @"closeAd", @"skipAd", @"adView", @"adBanner",
                        @"GADRequest", @"GADBanner", @"GADInterstitial", @"GADRewarded",
                        @"FBAdView", @"FBInterstitialAd", @"AdMob",
                        @"splashAd", @"interstitialAd", @"rewardedAd", @"bannerAd",
                        @"isAdLoaded", @"hasAd", @"adIsReady", @"showSplashAd",
                        @"buAd", @"csjAd", @"gdtAd", @"ttAd", @"ADView", @"ADBanner"];
        _vipKeywords = @[@"isVip", @"IsVip", @"hasVip", @"checkVip", @"vipStatus",
                         @"isMember", @"hasMember", @"isPremium", @"isPro",
                         @"isSubscribed", @"isSubscribing", @"hasActiveSubscription",
                         @"isPurchased", @"isUnlocked", @"isLocked",
                         @"canPlay", @"canAccess", @"hasPermission",
                         @"purchaseProduct", @"buyProduct", @"restorePurchase",
                         @"showPaywall", @"showPay", @"showIAP",
                         @"productId", @"productIdentifier", @"storeProduct",
                         @"receiptData", @"verifyReceipt", @"validateReceipt",
                         @"trialExpired", @"isTrial", @"trialEndDate",
                         @"unlockItem", @"lockItem", @"isRestricted",
                         @"shouldLockForProductIdentifier", @"isProductPurchased"];
        _customKeywords = @[];
    }
    return self;
}

#pragma mark - 智能扫描（关键词匹配）

- (void)scanSmartWithProgress:(void(^)(NSUInteger, NSUInteger))progress
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

                // 检查类名是否匹配关键词
                for (NSString *kw in allKeywords) {
                    if ([className localizedCaseInsensitiveContainsString:kw]) {
                        DHScannerResult *r = [DHScannerResult new];
                        r.methodName = @"(class)";
                        r.className = className;
                        r.matchedKeyword = kw;
                        if ([self.adKeywords containsObject:kw]) r.category = DHScannerCategoryAd;
                        else if ([self.vipKeywords containsObject:kw]) r.category = DHScannerCategoryVIP;
                        else r.category = DHScannerCategorySuspicious;
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
                    for (NSString *kw in allKeywords) {
                        if ([selName localizedCaseInsensitiveContainsString:kw]) {
                            DHScannerResult *r = [DHScannerResult new];
                            r.methodName = selName;
                            r.className = className;
                            r.matchedKeyword = kw;
                            if ([self.adKeywords containsObject:kw]) r.category = DHScannerCategoryAd;
                            else if ([self.vipKeywords containsObject:kw]) r.category = DHScannerCategoryVIP;
                            else r.category = DHScannerCategorySuspicious;
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

        DHLogInfo(@"智能扫描完成: %lu 条结果", (unsigned long)results.count);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(results); });
    });
}

#pragma mark - 全局扫描（全量dump）

- (void)scanAllClassesWithProgress:(void(^)(NSUInteger, NSUInteger))progress
                        completion:(void(^)(NSArray<DHScannerResult *> *))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *results = [NSMutableArray new];
        unsigned int classCount;
        Class *classes = objc_copyClassList(&classCount);

        for (unsigned int i = 0; i < classCount; i++) {
            @autoreleasepool {
                Class cls = classes[i];
                NSString *className = NSStringFromClass(cls);

                // 过滤纯系统框架类
                if ([className hasPrefix:@"NS"] || [className hasPrefix:@"UI"] ||
                    [className hasPrefix:@"CA"] || [className hasPrefix:@"CF"] ||
                    [className hasPrefix:@"WK"] || [className hasPrefix:@"AV"] ||
                    [className hasPrefix:@"OS"] || [className hasPrefix:@"DF"] ||
                    [className hasPrefix:@"LS"] || [className hasPrefix:@"SL"] ||
                    [className hasPrefix:@"TL"] || [className hasPrefix:@"TU"] ||
                    [className hasPrefix:@"MT"] || [className hasPrefix:@"MK"] ||
                    [className hasPrefix:@"CL"] || [className hasPrefix:@"CN"] ||
                    [className hasPrefix:@"MF"] || [className hasPrefix:@"PK"] ||
                    [className hasPrefix:@"_Tt"] ||
                    [className containsString:@"Proxy"] ||
                    [className containsString:@"Weak"]) {
                    continue;
                }

                // 跳过系统库
                const char *imgPath = class_getImageName(cls);
                if (imgPath) {
                    NSString *path = [NSString stringWithUTF8String:imgPath];
                    if ([path containsString:@"/System/Library/"] || [path containsString:@"/usr/lib/"]) continue;
                }
                // 跳过SwiftUI/Vision等系统前缀
                if ([className hasPrefix:@"SwiftUI."] || [className hasPrefix:@"Vision."] ||
                    [className hasPrefix:@"VisionCore."] || [className hasPrefix:@"Combine."] ||
                    [className hasPrefix:@"_SwiftUI"]) continue;

                // 添加类本身
                DHScannerResult *cr = [DHScannerResult new];
                cr.methodName = @"(class)";
                cr.className = className;
                cr.category = DHScannerCategorySuspicious;
                cr.matchedKeyword = @"";
                [results addObject:cr];

                // 遍历实例方法
                unsigned int methodCount;
                Method *methods = class_copyMethodList(cls, &methodCount);
                for (unsigned int j = 0; j < methodCount; j++) {
                    SEL sel = method_getName(methods[j]);
                    NSString *selName = NSStringFromSelector(sel);
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
                    DHScannerResult *r = [DHScannerResult new];
                    r.methodName = selName;
                    r.className = className;
                    r.category = DHScannerCategorySuspicious;
                    r.matchedKeyword = @"";
                    r.returnType = DHReturnTypeEncoding(methods[j]);
                    r.imageName = DHImageNameForClass(cls);
                    r.isClassMethod = NO;
                    r.fullSignature = DHBuildFullSignature(methods[j], NO);
                    [results addObject:r];
                }
                free(methods);

                // 遍历类方法（元类）
                unsigned int classMethodCount;
                Method *classMethods = class_copyMethodList(object_getClass(cls), &classMethodCount);
                for (unsigned int j = 0; j < classMethodCount; j++) {
                    SEL sel = method_getName(classMethods[j]);
                    NSString *selName = NSStringFromSelector(sel);
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
                    DHScannerResult *r = [DHScannerResult new];
                    r.methodName = selName;
                    r.className = className;
                    r.category = DHScannerCategorySuspicious;
                    r.matchedKeyword = @"";
                    r.returnType = DHReturnTypeEncoding(classMethods[j]);
                    r.imageName = DHImageNameForClass(cls);
                    r.isClassMethod = YES;
                    r.fullSignature = DHBuildFullSignature(classMethods[j], YES);
                    [results addObject:r];
                }
                free(classMethods);

                if (progress && i % 100 == 0) progress(i, classCount);
            }
        }
        free(classes);

        DHLogInfo(@"全局扫描完成: %lu 条结果", (unsigned long)results.count);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(results); });
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
    return text;
}

@end
