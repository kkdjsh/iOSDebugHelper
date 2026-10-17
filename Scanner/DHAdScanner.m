//
//  DHAdScanner.m
//  iOSDebugHelper
//  扫描全部已加载ObjC类和方法，不预设关键词过滤
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
        _adKeywords = @[];
        _vipKeywords = @[];
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

        for (unsigned int i = 0; i < classCount; i++) {
            @autoreleasepool {
                Class cls = classes[i];
                NSString *className = NSStringFromClass(cls);

                // 过滤掉纯系统框架类，但保留App自己的类（包括Swift类_Tt开头的）
                if ([className hasPrefix:@"NS"] || [className hasPrefix:@"UI"] ||
                    [className hasPrefix:@"CA"] || [className hasPrefix:@"CF"] ||
                    [className hasPrefix:@"WK"] || [className hasPrefix:@"AV"] ||
                    [className hasPrefix:@"OS"] || [className hasPrefix:@"DF"] ||
                    [className hasPrefix:@"LS"] || [className hasPrefix:@"SL"] ||
                    [className hasPrefix:@"TL"] || [className hasPrefix:@"TU"] ||
                    [className hasPrefix:@"MT"] || [className hasPrefix:@"MK"] ||
                    [className hasPrefix:@"CL"] || [className hasPrefix:@"CN"] ||
                    [className hasPrefix:@"MF"] || [className hasPrefix:@"PK"] ||
                    [className hasPrefix:@"_Tt"] ||  // 跳过Swift系统mangled name
                    [className containsString:@"Proxy"] ||
                    [className containsString:@"Weak"]) {
                    continue;
                }

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
                    // 过滤NSObject boilerplate
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
                    [results addObject:r];
                }
                free(methods);

                if (progress && i % 100 == 0) progress(i, classCount);
            }
        }
        free(classes);

        DHLogInfo(@"扫描完成: 共 %u 个类, %lu 条结果", classCount, (unsigned long)results.count);
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
