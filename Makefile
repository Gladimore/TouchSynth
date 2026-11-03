# Theos build: produces libTouchSynth.dylib. Run `make` with $THEOS set.
TARGET := iphone:clang:latest:14.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = libTouchSynth

libTouchSynth_FILES = $(wildcard Sources/TouchSynth/*.m) Sources/TouchSynth/TSTouchLogic.c
libTouchSynth_CFLAGS = -fobjc-arc -ISources/TouchSynth -ISources/TouchSynth/include
libTouchSynth_FRAMEWORKS = UIKit Foundation CoreGraphics
libTouchSynth_INSTALL_PATH = /usr/local/lib

include $(THEOS_MAKE_PATH)/library.mk
