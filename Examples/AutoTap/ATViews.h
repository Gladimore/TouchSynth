// Reusable overlay views: the launcher bubble, step markers and the settings panel.
#import <UIKit/UIKit.h>

#import "ATSession.h"

NS_ASSUME_NONNULL_BEGIN

UIColor *ATTapColor(void);
UIColor *ATSwipeColor(void);
UIColor *ATGoColor(void);
UIColor *ATStopColor(void);

// Lets touches through wherever it has no subview.
@interface ATPassthroughView : UIView
@end

// Floating launcher. Drag it anywhere; it snaps to the nearest side.
@interface ATBubbleView : UIView
@property (nonatomic, copy, nullable) void (^onTap)(void);
@property (nonatomic, copy, nullable) void (^onMoved)(CGPoint center);
@property (nonatomic, getter=isRunning) BOOL running;
@end

// A numbered, draggable handle marking where a step touches.
@interface ATMarkerView : UIView
- (instancetype)initWithNumber:(NSInteger)number color:(UIColor *)color diameter:(CGFloat)diameter;
@property (nonatomic, copy, nullable) void (^onDrag)(ATMarkerView *marker, BOOL finished);
@property (nonatomic, getter=isActive) BOOL active;
@end

@interface ATPanelView : UIView
- (instancetype)initWithSession:(ATSession *)session;
@property (nonatomic, copy, nullable) void (^onRecord)(void);
@property (nonatomic, copy, nullable) void (^onClose)(void);
@property (nonatomic, copy, nullable) void (^onToggleRun)(void);
- (void)reloadSteps;
- (void)updateRunState;
- (void)highlightStep:(NSInteger)index;
- (void)showMessage:(NSString *)message;
@end

NS_ASSUME_NONNULL_END
