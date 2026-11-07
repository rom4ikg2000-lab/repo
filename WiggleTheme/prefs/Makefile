TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME ?= rootless
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = WiggleThemePrefs
WiggleThemePrefs_FILES = RootListController.m
WiggleThemePrefs_CFLAGS = -fobjc-arc
WiggleThemePrefs_FRAMEWORKS = UIKit
WiggleThemePrefs_PRIVATE_FRAMEWORKS = Preferences
WiggleThemePrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
