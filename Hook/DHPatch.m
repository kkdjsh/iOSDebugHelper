//
//  DHPatch.m
//  iOSDebugHelper
//

#import "DHPatch.h"

@implementation DHPatch
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:self.patchName forKey:@"patchName"];
    [c encodeObject:self.hooks forKey:@"hooks"];
    [c encodeObject:self.rules forKey:@"rules"];
    [c encodeBool:self.enabled forKey:@"enabled"];
    [c encodeObject:self.createdAt forKey:@"createdAt"];
}
- (instancetype)initWithCoder:(NSCoder *)c {
    self = [super init];
    if (self) {
        _patchName = [c decodeObjectOfClass:NSString.class forKey:@"patchName"];
        _hooks = [c decodeObjectOfClasses:[NSSet setWithArray:@[NSArray.class, DHHookInfo.class]] forKey:@"hooks"] ?: @[];
        _rules = [c decodeObjectOfClasses:[NSSet setWithArray:@[NSArray.class, DHInterceptRule.class]] forKey:@"rules"] ?: @[];
        _enabled = [c decodeBoolForKey:@"enabled"];
        _createdAt = [c decodeObjectOfClass:NSDate.class forKey:@"createdAt"] ?: [NSDate date];
    }
    return self;
}
@end
