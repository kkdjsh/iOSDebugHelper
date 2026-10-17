//
//  DHScannerResult.m
//  iOSDebugHelper
//

#import "DHAdScanner.h"

@implementation DHScannerResult

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ In Class: %@", self.methodName, self.className];
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding { return YES; }

- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:self.methodName forKey:@"methodName"];
    [c encodeObject:self.className forKey:@"className"];
    [c encodeInteger:self.category forKey:@"category"];
    [c encodeObject:self.matchedKeyword forKey:@"matchedKeyword"];
}

- (instancetype)initWithCoder:(NSCoder *)c {
    self = [super init];
    if (self) {
        _methodName = [c decodeObjectOfClass:[NSString class] forKey:@"methodName"];
        _className = [c decodeObjectOfClass:[NSString class] forKey:@"className"];
        _category = [c decodeIntegerForKey:@"category"];
        _matchedKeyword = [c decodeObjectOfClass:[NSString class] forKey:@"matchedKeyword"];
    }
    return self;
}

@end
