TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME ?= rootless
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WiggleTheme
WiggleTheme_FILES = Tweak.xm
WiggleTheme_CFLAGS = -fobjc-arc
# rootless-билд видит обои в /var/jb, rootful — в корне; путь шейдера выбирается в Tweak.xm
ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
WiggleTheme_CFLAGS += -DWG_ROOTLESS=1
endif
WiggleTheme_FRAMEWORKS = UIKit CoreMotion Metal MetalKit

include $(THEOS_MAKE_PATH)/tweak.mk
