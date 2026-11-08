#import <Foundation/Foundation.h>

// Bundle identifiers are exact matches; app names are never used for exclusions.
static inline NSSet<NSString *> *FCExcludedBundleIDs(NSArray<NSString *> *values, BOOL hideOBS, NSString *obsID)
{
    NSMutableSet *ids = [NSMutableSet set];
    for (NSString *value in values) {
        NSString *trimmed = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length) [ids addObject:trimmed];
    }
    if (hideOBS && obsID.length) [ids addObject:obsID];
    return [ids copy];
}
