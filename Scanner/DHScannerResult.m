//
//  DHScannerResult.m
//  iOSDebugHelper
//

#import "DHAdScanner.h"

@implementation DHScannerResult
- (NSString *)description {
    return [NSString stringWithFormat:@"%@ In Class: %@", self.methodName, self.className];
}
@end
