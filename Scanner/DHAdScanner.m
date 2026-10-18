//
//  DHAdScanner.m
//  iOSDebugHelper
//  智能扫描(VIP/广告关键词) + 全局扫描(全量dump)
//

#import "DHAdScanner.h"
#import "DHLogManager.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString *DHTypeEncodingToObjC(const char *type) {
    if (!type) return @"id";
    NSString *s = [NSString stringWithUTF8String:type];
    if ([s isEqualToString:@"v"]) return @"void";
    if ([s isEqualToString:@"B"]) return @"BOOL";
    if ([s isEqualToString:@"c"]) return @"char";
    if ([s isEqualToString:@"C"]) return @"unsigned char";
    if ([s isEqualToString:@"i"]) return @"NSInteger";
    if ([s isEqualToString:@"s"]) return @"short";
    if ([s isEqualToString:@"l"]) return @"long";
    if ([s isEqualToString:@"q"]) return @"NSInteger";
    if ([s isEqualToString:@"I"]) return @"NSUInteger";
    if ([s isEqualToString:@"L"]) return @"unsigned long";
    if ([s isEqualToString:@"Q"]) return @"NSUInteger";
    if ([s isEqualToString:@"f"]) return @"CGFloat";
    if ([s isEqualToString:@"d"]) return @"double";
    if ([s isEqualToString:@"@"]) return @"id";
    if ([s isEqualToString:@"#"]) return @"Class";
    if ([s isEqualToString:@":"]) return @"SEL";
    if ([s isEqualToString:@"*"]) return @"char *";
    if ([s isEqualToString:@"^v"]) return @"void *";
    // 对象类型带类名，如 @"NSString"
    if ([s hasPrefix:@"@\""]) {
        NSUInteger end = [s rangeOfString:@"\"" options:0 range:NSMakeRange(2, s.length-2)].location;
        if (end != NSNotFound) {
            NSString *cls = [s substringWithRange:NSMakeRange(2, end-2)];
            return [NSString stringWithFormat:@"%@ *", cls];
        }
    }
    // block: @?
    if ([s isEqualToString:@"@?"]) return @"block";
    // 结构体 {=...}
    if ([s hasPrefix:@"{"]) return @"struct";
    // 其他指针
    if ([s hasPrefix:@"^"]) return @"void *";
    return @"id";
}

static NSString *DHReturnTypeEncoding(Method m) {
    const char *ret = method_copyReturnType(m);
    NSString *s = DHTypeEncodingToObjC(ret);
    free((void *)ret);
    return s;
}

// 解析方法的第n个参数类型（0-based，跳过self和_cmd）
static NSString *DHArgumentTypeAtIndex(Method m, NSUInteger argIndex) {
    // method_getTypeEncoding 格式: 返回类型 + @ + : + 参数1 + 参数2 + ...
    // self是@, _cmd是:
    const char *types = method_getTypeEncoding(m);
    if (!types) return @"id";

    // 先跳过返回类型（可能是结构体等复杂类型，需要跳过{}）
    NSUInteger pos = 0;
    typesSkipType(types, &pos);
    // 跳过 self (类型@) 和 _cmd (类型:)
    pos++; // self
    pos++; // _cmd

    // 现在跳到目标参数
    for (NSUInteger i = 0; i < argIndex; i++) {
        typesSkipType(types, &pos);
    }

    // 读取当前参数类型
    char buf[256];
    NSUInteger start = pos;
    typesSkipType(types, &pos);
    NSUInteger len = pos - start;
    if (len >= sizeof(buf)) len = sizeof(buf)-1;
    strncpy(buf, types + start, len);
    buf[len] = 0;
    return DHTypeEncodingToObjC(buf);
}

static void typesSkipType(const char *types, NSUInteger *pos) {
    char c = types[*pos];
    if (c == 0) return;
    // 结构体/联合体/数组 需要跳到匹配的结束符
    if (c == '{' || c == '(' || c == '[') {
        char open = c, close = (c=='{')?'}' : (c=='(')?')' : ']';
        (*pos)++;
        int depth = 1;
        while (types[*pos] && depth > 0) {
            if (types[*pos] == open) depth++;
            else if (types[*pos] == close) depth--;
            (*pos)++;
        }
        return;
    }
    // @"NSString" 带引号
    if (c == '@' && types[*pos+1] == '"') {
        (*pos) += 2;
        while (types[*pos] && types[*pos] != '"') (*pos)++;
        (*pos)++;
        return;
    }
    // 指针 ^ 后面跟一个类型
    if (c == '^') {
        (*pos)++;
        typesSkipType(types, pos);
        return;
    }
    // 基本类型只占1个字符
    (*pos)++;
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
    NSUInteger argIdx = 0;
    for (NSUInteger i = 0; i < parts.count; i++) {
        NSString *part = parts[i];
        if (part.length == 0) continue;
        NSString *argType = DHArgumentTypeAtIndex(m, argIdx);
        if (argIdx == 0) [sig appendFormat:@"%@:(%@)arg%lu", part, argType, (unsigned long)(argIdx+1)];
        else [sig appendFormat:@" %@:(%@)arg%lu", part, argType, (unsigned long)(argIdx+1)];
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
        _customKeywords = @[];
    }
    return self;
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
