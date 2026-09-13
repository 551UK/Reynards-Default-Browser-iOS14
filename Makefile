export ARCHS = arm64 arm64e
export TARGET = iphone:clang:14.5:14.0
export THEOS_PACKAGE_SCHEME =
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ReynardDefault
ReynardDefault_FILES = Tweak.x
ReynardDefault_CFLAGS = -fobjc-arc
ReynardDefault_FRAMEWORKS = Foundation UIKit

SUBPROJECTS = ReynardDefaultPrefs ReynardDefaultCC
include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

.PHONY: rootful
rootful:
	$(MAKE) clean
	$(MAKE) package FINALPACKAGE=1
