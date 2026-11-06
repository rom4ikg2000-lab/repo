TARGET := iphone:clang:latest:15.0
# ?= позволяет переопределить с консоли: make THEOS_PACKAGE_SCHEME=rootful
THEOS_PACKAGE_SCHEME ?= rootless
ARCHS = arm64

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OriginDroplet
OriginDroplet_FILES = Tweak.x
OriginDroplet_CFLAGS = -fobjc-arc
OriginDroplet_FRAMEWORKS = UIKit CoreMotion

include $(THEOS_MAKE_PATH)/tweak.mk
