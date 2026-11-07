#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface OriginDropletPrefsRootListController : PSListController
@end

@implementation OriginDropletPrefsRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [[self loadSpecifiersFromPlistName:@"OriginDropletPrefs" target:self] mutableCopy];
    }
    return _specifiers;
}

@end
