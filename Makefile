THEOS_PACKAGE_SCHEME = rootless
export THEOS=/opt/theos

TARGET := iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = iOSDebugHelper

iOSDebugHelper_FILES = Tweak.x \
    Logger/DHLogManager.m \
    Network/DHRuleManager.m \
    Network/DHInterceptRule.m \
    Network/DHNetworkInterceptor.m \
    Hook/DHHookManager.m \
    Hook/DHMonitorManager.m \
    Hook/DHHookInfo.m \
    Hook/DHPatch.m \
    Crypto/DHCryptManager.m \
    Scanner/DHAdScanner.m \
    Scanner/DHScannerResult.m \
    AI/DHAIManager.m \
    AI/DHKeepAliveManager.m \
    UI/DHButtonManager.m \
    UI/DHMainMenuViewController.m \
    UI/DHViewInspectorVC.m \
    UI/DHKeywordVC.m \
    UI/DHBuiltinKeywords.m

iOSDebugHelper_CFLAGS = -fobjc-arc -fmodules -Wno-everything -I. -ILogger -INetwork -IHook -ICrypto -IScanner -IAI -IUI
iOSDebugHelper_CXXFLAGS = -std=c++14
iOSDebugHelper_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore Security JavaScriptCore AVFoundation UserNotifications WebKit SceneKit ImageIO
iOSDebugHelper_LIBRARIES = substrate sqlite3 z

include $(THEOS_MAKE_PATH)/tweak.mk
