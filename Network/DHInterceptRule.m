//
//  DHInterceptRule.m
//  iOSDebugHelper
//

#import "DHInterceptRule.h"
#import "DHLogManager.h"

@implementation DHJSONPatchItem
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:self.keyPath forKey:@"keyPath"];
    [c encodeObject:self.valueString forKey:@"valueString"];
}
- (instancetype)initWithCoder:(NSCoder *)c {
    self = [super init];
    if (self) {
        _keyPath = [c decodeObjectOfClass:NSString.class forKey:@"keyPath"];
        _valueString = [c decodeObjectOfClass:NSString.class forKey:@"valueString"];
    }
    return self;
}
@end

@implementation DHHeaderOverride
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:self.headerName forKey:@"headerName"];
    [c encodeObject:self.headerValue forKey:@"headerValue"];
}
- (instancetype)initWithCoder:(NSCoder *)c {
    self = [super init];
    if (self) {
        _headerName = [c decodeObjectOfClass:NSString.class forKey:@"headerName"];
        _headerValue = [c decodeObjectOfClass:NSString.class forKey:@"headerValue"];
    }
    return self;
}
@end

@implementation DHInterceptRule
+ (BOOL)supportsSecureCoding { return YES; }

- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:self.urlPattern forKey:@"urlPattern"];
    [c encodeInteger:self.matchType forKey:@"matchType"];
    [c encodeBool:self.enabled forKey:@"enabled"];
    [c encodeObject:self.patches forKey:@"patches"];
    [c encodeObject:self.requestHeaderOverrides forKey:@"requestHeaderOverrides"];
    [c encodeBool:self.applyCookieToStorage forKey:@"applyCookieToStorage"];
}

- (instancetype)initWithCoder:(NSCoder *)c {
    self = [super init];
    if (self) {
        _urlPattern = [c decodeObjectOfClass:NSString.class forKey:@"urlPattern"];
        _matchType = [c decodeIntegerForKey:@"matchType"];
        _enabled = [c decodeBoolForKey:@"enabled"];
        _patches = [c decodeObjectOfClasses:[NSSet setWithArray:@[NSArray.class, DHJSONPatchItem.class]] forKey:@"patches"] ?: @[];
        _requestHeaderOverrides = [c decodeObjectOfClasses:[NSSet setWithArray:@[NSArray.class, DHHeaderOverride.class]] forKey:@"requestHeaderOverrides"] ?: @[];
        _applyCookieToStorage = [c decodeBoolForKey:@"applyCookieToStorage"];
    }
    return self;
}

- (BOOL)matchesURL:(NSString *)url {
    if (!url.length || !self.urlPattern.length) return NO;
    NSError *err;
    if (self.matchType == DHMatchTypeRegex) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:self.urlPattern options:0 error:&err];
        if (err) { DHLogWarn(@"规则正则编译失败: %@", err); return NO; }
        NSUInteger count = [re numberOfMatchesInString:url options:0 range:NSMakeRange(0, url.length)];
        return count > 0;
    }
    return [url localizedCaseInsensitiveContainsString:self.urlPattern];
}

- (id)applyPatchesToJSON:(id)jsonObject {
    if (!self.patches.count) return jsonObject;
    id result = [jsonObject mutableCopy];
    for (DHJSONPatchItem *patch in self.patches) {
        result = [self applyPatch:patch toObject:result];
    }
    return result;
}

- (id)applyPatch:(DHJSONPatchItem *)patch toObject:(id)obj {
    NSMutableArray *components = [[patch.keyPath componentsSeparatedByString:@"."] mutableCopy];
    if (!components.count) return obj;

    NSString *lastKey = components.lastObject;
    [components removeLastObject];

    id current = obj;
    for (NSString *key in components) {
        if ([current isKindOfClass:NSDictionary.class]) {
            current = current[key];
            if (!current) return obj;
        } else {
            return obj;
        }
    }

    if ([current isKindOfClass:NSMutableDictionary.class]) {
        current[lastKey] = [self valueFromString:patch.valueString];
    }
    return obj;
}

- (id)valueFromString:(NSString *)str {
    if ([str isEqualToString:@"true"])  return @(YES);
    if ([str isEqualToString:@"false"]) return @(NO);
    if ([str isEqualToString:@"nil"])   return [NSNull null];
    if ([str hasPrefix:@"\""] && [str hasSuffix:@"\""]) {
        return [str substringWithRange:NSMakeRange(1, str.length - 2)];
    }
    NSNumberFormatter *f = [NSNumberFormatter new];
    NSNumber *num = [f numberFromString:str];
    if (num) return num;
    return str;
}

@end
