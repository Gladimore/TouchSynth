# Plain dylib for Sideloadly-style injection: no Substrate, the constructor in
# AutoTap.m starts everything. TouchSynth is compiled in from this repo.
ARCHS = arm64
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

TOUCHSYNTH = ../../Sources/TouchSynth

LIBRARY_NAME = AutoTap

AutoTap_FILES = AutoTap.m ATSession.m ATViews.m \
	$(TOUCHSYNTH)/TSPrivateUIKit.m $(TOUCHSYNTH)/TSTouchSynthesizer.m $(TOUCHSYNTH)/TSTouchLogic.c
AutoTap_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
AutoTap_CFLAGS = -fobjc-arc -O2 -Wall -Wno-unused-parameter -Wno-deprecated-declarations \
	-I$(TOUCHSYNTH) -I$(TOUCHSYNTH)/include

include $(THEOS_MAKE_PATH)/library.mk
