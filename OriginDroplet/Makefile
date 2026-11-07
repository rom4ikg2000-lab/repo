TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME ?= rootless
ARCHS = arm64

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += tweak prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
