TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME ?= rootless
ARCHS = arm64

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += tweak prefs
include $(THEOS_MAKE_PATH)/aggregate.mk

# .metal не компилируется Theos'ом — кладём исходник в пакет,
# твик компилирует его в MTLLibrary на устройстве при первом запуске.
# ВАЖНО: в rootless-схеме Theos сам добавляет /var/jb ко всем путям,
# поэтому в staging пишем БЕЗ префикса var/jb.
after-stage::
	mkdir -p "$(THEOS_STAGING_DIR)/Library/Application Support/WiggleTheme"
	cp tweak/WallpaperShader.metal "$(THEOS_STAGING_DIR)/Library/Application Support/WiggleTheme/WallpaperShader.metal"
