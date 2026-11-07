#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

@interface WiggleThemePrefsRootListController : PSListController
@end

@implementation WiggleThemePrefsRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [[self loadSpecifiersFromPlistName:@"WiggleThemePrefs" target:self] mutableCopy];
    }
    return _specifiers;
}

- (void)openMaskEditor {
    Class editorClass = NSClassFromString(@"WGMaskEditorController");
    if (!editorClass) return;
    UIViewController *editor = [[editorClass alloc] init];
    [self.navigationController pushViewController:editor animated:YES];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.wiggletheme.preferenceschanged"), NULL, NULL, true);
}

@end
