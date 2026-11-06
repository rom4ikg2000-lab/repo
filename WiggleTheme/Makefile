TARGET := iphone:clang:latest:16.0
# ?= позволяет переопределить с консоли: make THEOS_PACKAGE_SCHEME=rootful
THEOS_PACKAGE_SCHEME ?= rootless
ARCHS = arm64

INSTALL_TARGET_PROCESSES = SpringBoard

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

# .metal не компилируется Theos'ом — кладём исходник в пакет,
# твик компилирует его в MTLLibrary на устройстве при первом запуске.
# ВАЖНО: в rootless-схеме Theos сам добавляет /var/jb ко всем путям,
# поэтому в staging пишем БЕЗ префикса var/jb.
after-stage::
	mkdir -p "$(THEOS_STAGING_DIR)/Library/Application Support/WiggleTheme"
	cp WallpaperShader.metal "$(THEOS_STAGING_DIR)/Library/Application Support/WiggleTheme/WallpaperShader.metal"
