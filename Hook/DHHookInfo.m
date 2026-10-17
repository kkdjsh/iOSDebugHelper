//
//  DHHookInfo.m
//  iOSDebugHelper
//

#import "DHHookInfo.h"

@implementation DHHookInfo
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:self.className forKey:@"className"];
    [c encodeObject:self.selectorName forKey:@"selectorName"];
    [c encodeBool:self.isClassMethod forKey:@"isClassMethod"];
    [c encodeInteger:self.returnType forKey:@"returnType"];
    [c encodeObject:self.customValue forKey:@"customValue"];
    [c encodeObject:self.reason forKey:@"reason"];
}
- (instancetype)initWithCoder:(NSCoder *)c {
    self = [super init];
    if (self) {
        _className = [c decodeObjectOfClass:NSString.class forKey:@"className"];
        _selectorName = [c decodeObjectOfClass:NSString.class forKey:@"selectorName"];
        _isClassMethod = [c decodeBoolForKey:@"isClassMethod"];
        _returnType = [c decodeIntegerForKey:@"returnType"];
        _customValue = [c decodeObjectForKey:@"customValue"];
        _reason = [c decodeObjectOfClass:NSString.class forKey:@"reason"];
    }
    return self;
}
@end
