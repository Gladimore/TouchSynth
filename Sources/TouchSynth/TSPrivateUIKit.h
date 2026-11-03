// UITouch and UIEvent construction through private UIKit state.
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Installs the UITouch and UIApplication hooks. Safe to call repeatedly.
void TSInstallHooks(void);

// Control-action tracking: counts actions UIKit really sent for the tracked control.
void TSTrackControl(UIControl *_Nullable control);
UIControl *_Nullable TSTrackedControl(void);
long TSTrackedActionCount(void);

UITouch *_Nullable TSCreateTouch(UIWindow *window, UIView *view, CGPoint windowPoint);
void TSTouchSetWindowAndView(UITouch *touch, UIWindow *window, UIView *_Nullable view);
void TSTouchSetPhase(UITouch *touch, UITouchPhase phase);
void TSTouchSetLocation(UITouch *touch, CGPoint windowPoint);
void TSTouchSetIdentifier(UITouch *touch, NSInteger identifier);
NSInteger TSTouchGetIdentifier(UITouch *touch);
void TSTouchSetTapFlag(UITouch *touch, BOOL isTap);
BOOL TSTouchGetTapFlag(UITouch *touch);

// nil when UIKit has no _initWithEvent:touches: or it fails. Callers fall through
// to the direct stage, which accepts a nil event.
UIEvent *_Nullable TSCreateEvent(UITouch *touch);

NSDictionary<NSString *, NSNumber *> *TSPrivateRuntimeDiagnostics(void);

NS_ASSUME_NONNULL_END
