TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME ?= rootless
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = OriginDropletPrefs
OriginDropletPrefs_FILES = RootListController.m
OriginDropletPrefs_CFLAGS = -fobjc-arc
OriginDropletPrefs_FRAMEWORKS = UIKit
OriginDropletPrefs_PRIVATE_FRAMEWORKS = Preferences
OriginDropletPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
