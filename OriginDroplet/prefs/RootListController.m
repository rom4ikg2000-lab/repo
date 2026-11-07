#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <spawn.h>

#define OD_PREFS_ID CFSTR("com.origindroplet.defaults")

@interface OriginDropletPrefsRootListController : PSListController
@end

@implementation OriginDropletPrefsRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [[self loadSpecifiersFromPlistName:@"OriginDropletPrefs" target:self] mutableCopy];
    }
    return _specifiers;
}

// кнопка «Поставить каплю в центр зоны»: твик подхватывает флаг и переставляет каплю
- (void)centerDroplet:(PSSpecifier *)specifier {
    CFPreferencesSetValue(CFSTR("CenterRequested"), kCFBooleanTrue,
                          OD_PREFS_ID, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost);
    CFPreferencesAppSynchronize(OD_PREFS_ID);
}

- (void)respring:(PSSpecifier *)specifier {
    pid_t pid;
    const char *argv[] = { "killall", "-9", "SpringBoard", NULL };
    posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char *const *)argv, NULL);
}

@end
