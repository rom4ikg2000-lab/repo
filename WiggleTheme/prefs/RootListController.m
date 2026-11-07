#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface WiggleThemePrefsRootListController : PSListController
@end

@implementation WiggleThemePrefsRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [[self loadSpecifiersFromPlistName:@"WiggleThemePrefs" target:self] mutableCopy];
    }
    return _specifiers;
}

@end
