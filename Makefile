ARCHS = arm64
TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = Horrorfield

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HorrorfieldMod

HorrorfieldMod_FILES = Tweak.xm
HorrorfieldMod_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable
HorrorfieldMod_CCFLAGS = -std=c++17
HorrorfieldMod_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
