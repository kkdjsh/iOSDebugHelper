//
//  DHButtonManager.h
//  iOSDebugHelper
//  悬浮球管理：可拖拽、可调大小/透明度/位置
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DHButtonManager : NSObject

@property (nonatomic, strong) UIButton *floatingButton;
@property (nonatomic, assign) CGFloat buttonSize;      // 默认 60
@property (nonatomic, assign) CGFloat buttonAlpha;     // 默认 0.7
@property (nonatomic, assign) CGPoint buttonPosition;

+ (instancetype)sharedManager;

/// 显示悬浮按钮
- (void)showFloatingButton;

/// 隐藏悬浮按钮
- (void)hideFloatingButton;

/// 重置位置到屏幕左下
- (void)resetPosition;

/// 保存设置到 NSUserDefaults
- (void)saveSettings;
- (void)loadSettings;

@end

NS_ASSUME_NONNULL_END
