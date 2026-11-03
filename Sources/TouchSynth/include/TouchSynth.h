// TouchSynth: in-process UIKit touch synthesis, reimplemented from the replay
// engine in iGameGod 0.8.3. It only reaches windows of the process it runs in.
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TSTouchAction) {
    TSTouchActionBegan = 0,
    TSTouchActionMoved = 1,
    TSTouchActionEnded = 2,
    TSTouchActionCancelled = 3,
};

// Each stage of the delivery chain can be turned off independently.
typedef NS_OPTIONS(NSUInteger, TSDeliveryOptions) {
    TSDeliverySendEvent = 1 << 0,      // -[UIWindow sendEvent:] with a UITouchesEvent
    TSDeliveryDirectTouches = 1 << 1,  // touchesBegan: etc. straight to the hit view
    TSDeliveryControlActions = 1 << 2, // sendActionsForControlEvents: on UIControls
    TSDeliveryTapGestures = 1 << 3,    // invoke UITapGestureRecognizer targets
    TSDeliveryPanGestures = 1 << 4,    // invoke UIPanGestureRecognizer targets
    TSDeliveryScrollViews = 1 << 5,    // drive UIScrollView contentOffset
    TSDeliveryCellSelection = 1 << 6,  // table and collection view selection
    TSDeliveryAll = 0x7F,
};

// One step of a touch. Points are in screen coordinates (UIScreen.coordinateSpace).
@interface TSTouchEvent : NSObject
@property (nonatomic) NSInteger identifier; // same value from began through ended
@property (nonatomic) TSTouchAction action;
@property (nonatomic) CGPoint point;
// Optional: prefer a window of this class and/or level, as iGameGod's recordings do.
@property (nonatomic, copy, nullable) NSString *windowClassName;
@property (nonatomic, strong, nullable) NSNumber *windowLevel;
+ (instancetype)eventWithIdentifier:(NSInteger)identifier action:(TSTouchAction)action point:(CGPoint)point;
@end

// All methods may be called from any thread. Off the main thread they are queued
// to it in order, and methods returning BOOL return YES for "queued".
@interface TSTouchSynthesizer : NSObject

@property (class, nonatomic, readonly) TSTouchSynthesizer *sharedSynthesizer;

// Your own overlay: never hit-tested, and interaction is suspended during dispatch.
@property (nonatomic, weak, nullable) UIView *excludedView;
@property (nonatomic) TSDeliveryOptions deliveryOptions; // default TSDeliveryAll
@property (nonatomic) BOOL verboseLogging;

// Low-level entry point. NO when no window or view is at the point, the identifier
// has no touch in progress, or UITouch no longer has the expected private ivars.
- (BOOL)sendEvent:(TSTouchEvent *)event;

- (BOOL)touchDownWithIdentifier:(NSInteger)identifier atPoint:(CGPoint)point;
- (BOOL)touchMoveWithIdentifier:(NSInteger)identifier toPoint:(CGPoint)point;
- (BOOL)touchUpWithIdentifier:(NSInteger)identifier atPoint:(CGPoint)point;
- (BOOL)touchCancelWithIdentifier:(NSInteger)identifier atPoint:(CGPoint)point;

// Cancels every touch in progress and any running tap or swipe.
- (void)cancelAllTouches;

// finished is NO if cancelled, or if the touch could not start.
- (void)tapAtPoint:(CGPoint)point;
- (void)tapAtPoint:(CGPoint)point
          duration:(NSTimeInterval)duration
        completion:(nullable void (^)(BOOL finished))completion;
- (void)swipeFromPoint:(CGPoint)from
               toPoint:(CGPoint)to
              duration:(NSTimeInterval)duration
            completion:(nullable void (^)(BOOL finished))completion;

// Which private UIKit pieces exist on this iOS version. Log this first on a new
// OS: a NO under "event" means only the direct and fallback stages can work.
+ (NSDictionary<NSString *, NSNumber *> *)runtimeDiagnostics;

@end

// C interface for tweaks, game engines and FFI callers.
#ifdef __cplusplus
extern "C" {
#endif
bool TSTouchDown(long identifier, double x, double y);
bool TSTouchMove(long identifier, double x, double y);
bool TSTouchUp(long identifier, double x, double y);
bool TSTouchCancel(long identifier, double x, double y);
void TSTouchCancelAll(void);
void TSTap(double x, double y);
void TSSwipe(double fromX, double fromY, double toX, double toY, double duration);
#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
