#import <Foundation/Foundation.h>
#import "capture-policy.h"
#include <assert.h>

int main(void)
{
    @autoreleasepool {
        NSSet *ids = FCExcludedBundleIDs(@[@" io.simplelocalize.notch-prompter ", @"", @"com.apple.Notes", @"com.apple.Notes"], YES, @"com.obsproject.obs-studio");
        assert(ids.count == 3);
        assert([ids containsObject:@"io.simplelocalize.notch-prompter"]);
        assert(![ids containsObject:@"io.simplelocalize.notch-prompter.other"]);
        assert([ids containsObject:@"com.obsproject.obs-studio"]);
        assert(![FCExcludedBundleIDs(@[], NO, @"com.obsproject.obs-studio") containsObject:@"com.obsproject.obs-studio"]);
        assert(FCExcludedBundleIDs(@[@" \n "], YES, nil).count == 0);
        puts("PASS: exact bundle ID matching, whitespace, deduplication, optional OBS exclusion, empty input");
    }
}
