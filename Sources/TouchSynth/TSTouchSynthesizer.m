#import "TouchSynth.h"

#import <math.h>
#import <objc/runtime.h>

#import "TSPrivateUIKit.h"
#import "TSTouchLogic.h"

static const NSInteger kGestureSearchDepth = 8;
static const CGFloat kMinimumVisibleAlpha = 0.01;
static const CGFloat kOffsetEpsilon = 0.5;
static const CGFloat kWindowLevelEpsilon = 0.001;
static const NSTimeInterval kDefaultTapDuration = 0.05;
static const NSTimeInterval kSwipeStepInterval = 1.0 / 60.0;
static const NSInteger kFirstGeneratedIdentifier = 1 << 20;

static const NSInteger kGestureStateBegan = 1;
static const NSInteger kGestureStateChanged = 2;
static const NSInteger kGestureStateEnded = 3;
static const NSInteger kGestureStateCancelled = 4;

#define TSLog(...) do { if (self.verboseLogging) NSLog(@"[TouchSynth] " __VA_ARGS__); } while (0)

@implementation TSTouchEvent
+ (instancetype)eventWithIdentifier:(NSInteger)identifier action:(TSTouchAction)action point:(CGPoint)point {
    TSTouchEvent *event = [[self alloc] init];
    event.identifier = identifier;
    event.action = action;
    event.point = point;
    return event;
}
@end

// Per-touch bookkeeping, one for each identifier between began and ended.
@interface TSTouchState : NSObject
@property (nonatomic) NSInteger identifier;
@property (nonatomic, strong) UITouch *touch;
@property (nonatomic, weak) UIWindow *window;
@property (nonatomic, weak) UIView *view;
@property (nonatomic, weak) UIControl *control;
@property (nonatomic, weak) UIScrollView *scrollView;
@property (nonatomic, copy) NSArray<UIPanGestureRecognizer *> *panGestures;
@property (nonatomic) CGPoint startPoint;
@property (nonatomic) CGPoint startContentOffset;
@property (nonatomic) BOOL panActive;
@property (nonatomic) BOOL movedPastTapSlop;
@end

@implementation TSTouchState
@end

#pragma mark - Gesture target safety

static id TSTryValue(id object, NSString *key) {
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static BOOL TSBundleIsAppOwned(NSBundle *bundle) {
    if (!bundle) {
        return NO;
    }
    NSBundle *main = [NSBundle mainBundle];
    if (bundle == main) {
        return YES;
    }
    return bundle.bundlePath.length > 0 && main.bundlePath.length > 0 && [bundle.bundlePath hasPrefix:main.bundlePath];
}

static BOOL TSClassNameLooksWebKit(NSString *name) {
    return [name hasPrefix:@"WK"] || [name hasPrefix:@"_WK"] || [name hasPrefix:@"Web"] || [name containsString:@"WebKit"];
}

// Forcing state on system or WebKit recognizers can break their internal state
// machines, so only targets in the app's own code (or third party bundles) qualify.
static BOOL TSClassIsSafeTarget(Class cls) {
    NSBundle *bundle = [NSBundle bundleForClass:cls];
    if (TSBundleIsAppOwned(bundle)) {
        return YES;
    }
    if (TSClassNameLooksWebKit(NSStringFromClass(cls))) {
        return NO;
    }
    NSString *path = bundle.bundlePath;
    return path.length > 0 && ![path hasPrefix:@"/System/Library/"] && ![path containsString:@"/PrivateFrameworks/"];
}

static NSArray *TSGestureTargetEntries(UIGestureRecognizer *gesture) {
    id entries = TSTryValue(gesture, @"_targets");
    return [entries isKindOfClass:[NSArray class]] ? entries : @[];
}

static id TSGestureEntryTarget(id entry) {
    return TSTryValue(entry, @"_target") ?: TSTryValue(entry, @"target");
}

static NSString *TSGestureEntrySelectorName(id entry) {
    id action = TSTryValue(entry, @"_action") ?: TSTryValue(entry, @"action");
    if ([action isKindOfClass:[NSString class]]) {
        return action;
    }
    if ([action isKindOfClass:[NSValue class]]) {
        void *pointer = [(NSValue *)action pointerValue];
        return pointer ? NSStringFromSelector((SEL)pointer) : nil;
    }
    return [action respondsToSelector:@selector(description)] ? [action description] : nil;
}

static BOOL TSGestureIsSafeToInvoke(UIGestureRecognizer *gesture) {
    NSArray *entries = TSGestureTargetEntries(gesture);
    if (entries.count == 0) {
        return NO;
    }
    Class gestureClass = object_getClass(gesture);
    if (!TSBundleIsAppOwned([NSBundle bundleForClass:gestureClass]) &&
        TSClassNameLooksWebKit(NSStringFromClass(gestureClass))) {
        return NO;
    }
    for (id entry in entries) {
        id target = TSGestureEntryTarget(entry);
        if (target && TSGestureEntrySelectorName(entry).length > 0 && !TSClassIsSafeTarget(object_getClass(target))) {
            return NO;
        }
    }
    return YES;
}

// Runs the recognizer's action targets as if it reached `state`, then restores it.
static NSUInteger TSInvokeGesture(UIGestureRecognizer *gesture, NSInteger state) {
    if (!TSGestureIsSafeToInvoke(gesture)) {
        return 0;
    }
    NSInteger previous = gesture.state;
    @try {
        [gesture setValue:@(state) forKey:@"state"];
    } @catch (__unused NSException *exception) {
        return 0;
    }
    NSUInteger invoked = 0;
    for (id entry in TSGestureTargetEntries(gesture)) {
        id target = TSGestureEntryTarget(entry);
        NSString *name = TSGestureEntrySelectorName(entry);
        if (target && name.length > 0) {
            [[UIApplication sharedApplication] sendAction:NSSelectorFromString(name) to:target from:gesture forEvent:nil];
            invoked++;
        }
    }
    @try {
        [gesture setValue:@(previous) forKey:@"state"];
    } @catch (__unused NSException *exception) {
    }
    return invoked;
}

// First ancestor level with usable recognizers of `cls` wins, up to 8 levels up.
static NSArray *TSFindGestures(UIView *view, Class cls) {
    NSMutableArray *found = [NSMutableArray array];
    for (NSInteger depth = 0; view && depth < kGestureSearchDepth; depth++, view = view.superview) {
        for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
            if ([gesture isKindOfClass:cls] && gesture.enabled && TSGestureIsSafeToInvoke(gesture)) {
                [found addObject:gesture];
            }
        }
        if (found.count > 0) {
            break;
        }
    }
    return found;
}

#pragma mark - View helpers

static UIControl *TSNearestControl(UIView *view) {
    for (; view; view = view.superview) {
        if ([view isKindOfClass:[UIControl class]]) {
            return (UIControl *)view;
        }
    }
    return nil;
}

static UIScrollView *TSNearestScrollView(UIView *view) {
    for (; view; view = view.superview) {
        if ([view isKindOfClass:[UIScrollView class]]) {
            UIScrollView *scrollView = (UIScrollView *)view;
            if (scrollView.scrollEnabled && !scrollView.hidden && scrollView.alpha > kMinimumVisibleAlpha) {
                return scrollView;
            }
        }
    }
    return nil;
}

static UIView *TSNearestCell(UIView *view) {
    for (NSInteger depth = 0; view && depth < kGestureSearchDepth; depth++, view = view.superview) {
        if ([view isKindOfClass:[UICollectionViewCell class]] || [view isKindOfClass:[UITableViewCell class]]) {
            return view;
        }
    }
    return nil;
}

static BOOL TSSceneIsForegroundActive(UIWindow *window) {
    UIWindowScene *scene = window.windowScene;
    return !scene || scene.activationState == UISceneActivationStateForegroundActive || scene.activationState == UISceneActivationStateForegroundInactive;
}

static CGPoint TSScreenToWindow(UIWindow *window, CGPoint point) {
    return [window.screen.coordinateSpace convertPoint:point toCoordinateSpace:window.coordinateSpace];
}

static NSSet *TSTouchSet(UITouch *touch) {
    return [NSSet setWithObject:touch];
}

// Port of FUN_0058eb90.
static BOOL TSDeliverDirect(UITouch *touch, UIView *view, UIEvent *event) {
    NSSet *touches = TSTouchSet(touch);
    switch (touch.phase) {
        case UITouchPhaseBegan:
            [view touchesBegan:touches withEvent:event];
            return YES;
        case UITouchPhaseMoved:
            [view touchesMoved:touches withEvent:event];
            return YES;
        case UITouchPhaseEnded:
            [view touchesEnded:touches withEvent:event];
            return YES;
        case UITouchPhaseCancelled:
            [view touchesCancelled:touches withEvent:event];
            return YES;
        default:
            return NO;
    }
}

#pragma mark - Synthesizer

@implementation TSTouchSynthesizer {
    NSMutableDictionary<NSNumber *, TSTouchState *> *_states;
    NSInteger _nextIdentifier;
    NSUInteger _sequenceGeneration;
}

+ (TSTouchSynthesizer *)sharedSynthesizer {
    static TSTouchSynthesizer *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[TSTouchSynthesizer alloc] init];
    });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _states = [NSMutableDictionary dictionary];
        _deliveryOptions = TSDeliveryAll;
        _nextIdentifier = kFirstGeneratedIdentifier;
    }
    return self;
}

+ (NSDictionary<NSString *, NSNumber *> *)runtimeDiagnostics {
    return TSPrivateRuntimeDiagnostics();
}

#pragma mark Excluded view

// Runs `block` with the excluded view's interaction off if it lives in `window`.
- (void)withExcludedViewDisabledInWindow:(UIWindow *)window perform:(void (^)(void))block {
    UIView *excluded = self.excludedView;
    if (excluded && excluded.window == window && excluded.userInteractionEnabled) {
        excluded.userInteractionEnabled = NO;
        block();
        excluded.userInteractionEnabled = YES;
    } else {
        block();
    }
}

// A window holding nothing visible except the excluded view is a pure overlay.
- (BOOL)windowIsOverlayOnly:(UIWindow *)window {
    UIView *excluded = self.excludedView;
    UIView *root = window.rootViewController.view;
    if (!excluded || excluded.window != window || !root) {
        return NO;
    }
    if (root == excluded) {
        return YES;
    }
    if (![excluded isDescendantOfView:root]) {
        return NO;
    }
    BOOL sawVisibleSubview = NO;
    for (UIView *subview in root.subviews) {
        if (subview.hidden || subview.alpha <= kMinimumVisibleAlpha) {
            continue;
        }
        sawVisibleSubview = YES;
        if (subview != excluded && ![subview isDescendantOfView:excluded]) {
            return NO;
        }
    }
    return sawVisibleSubview;
}

#pragma mark Window resolution

- (BOOL)windowIsEligible:(UIWindow *)window {
    return !window.hidden && window.alpha > kMinimumVisibleAlpha && window.userInteractionEnabled &&
           CGRectGetWidth(window.bounds) > 0 && CGRectGetHeight(window.bounds) > 0 &&
           ![self windowIsOverlayOnly:window] && TSSceneIsForegroundActive(window);
}

// Topmost first: higher level, then key window, then later in UIApplication.windows.
- (NSArray<UIWindow *> *)candidateWindows {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSArray<UIWindow *> *windows = [UIApplication sharedApplication].windows;
#pragma clang diagnostic pop
    NSMutableArray<UIWindow *> *eligible = [NSMutableArray array];
    for (UIWindow *window in windows) {
        if ([self windowIsEligible:window]) {
            [eligible addObject:window];
        }
    }
    return [eligible sortedArrayUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
        if (a.windowLevel != b.windowLevel) {
            return a.windowLevel > b.windowLevel ? NSOrderedAscending : NSOrderedDescending;
        }
        if (a.isKeyWindow != b.isKeyWindow) {
            return a.isKeyWindow ? NSOrderedAscending : NSOrderedDescending;
        }
        return [windows indexOfObject:a] > [windows indexOfObject:b] ? NSOrderedAscending : NSOrderedDescending;
    }];
}

// Port of FUN_00588c54. A hit on the bare window counts as nothing being there.
- (UIView *)hitViewInWindow:(UIWindow *)window atWindowPoint:(CGPoint)point {
    __block UIView *hit = nil;
    [self withExcludedViewDisabledInWindow:window perform:^{
        hit = [window hitTest:point withEvent:nil];
    }];
    UIView *excluded = self.excludedView;
    if (!hit || hit == window || (excluded && (hit == excluded || [hit isDescendantOfView:excluded]))) {
        return nil;
    }
    return hit;
}

- (BOOL)window:(UIWindow *)window matchesHintsOf:(TSTouchEvent *)event {
    if (event.windowClassName && ![NSStringFromClass(object_getClass(window)) isEqualToString:event.windowClassName]) {
        return NO;
    }
    return !event.windowLevel || fabs(window.windowLevel - event.windowLevel.doubleValue) < kWindowLevelEpsilon;
}

// Ports of FUN_00587c08 and FUN_00587d74: hinted window first, then top to bottom.
- (UIWindow *)resolveWindowForEvent:(TSTouchEvent *)event hitView:(UIView **)outView {
    NSArray<UIWindow *> *candidates = [self candidateWindows];
    if (event.windowClassName || event.windowLevel) {
        for (UIWindow *window in candidates) {
            if ([self window:window matchesHintsOf:event]) {
                CGPoint point = TSScreenToWindow(window, event.point);
                UIView *hit = CGRectContainsPoint(window.bounds, point) ? [self hitViewInWindow:window atWindowPoint:point] : nil;
                if (hit) {
                    *outView = hit;
                    return window;
                }
                break;
            }
        }
    }
    for (UIWindow *window in candidates) {
        CGPoint point = TSScreenToWindow(window, event.point);
        if (CGRectContainsPoint(window.bounds, point)) {
            UIView *hit = [self hitViewInWindow:window atWindowPoint:point];
            if (hit) {
                *outView = hit;
                return window;
            }
        }
    }
    return nil;
}

// Port of FUN_00587fb4: keep the touch's window if it still qualifies.
- (UIWindow *)continuingWindowForState:(TSTouchState *)state event:(TSTouchEvent *)event view:(UIView **)outView {
    UIWindow *window = state.touch.window ?: state.window;
    if (window && [self windowIsEligible:window] && [self window:window matchesHintsOf:event]) {
        CGPoint point = TSScreenToWindow(window, event.point);
        UIView *view = state.view ?: state.touch.view ?: [self hitViewInWindow:window atWindowPoint:point];
        if (view && CGRectContainsPoint(window.bounds, point)) {
            *outView = view;
            return window;
        }
    }
    return [self resolveWindowForEvent:event hitView:outView];
}

#pragma mark Touch lifecycle

// Port of FUN_00586e0c.
- (TSTouchState *)beginTouchForEvent:(TSTouchEvent *)event window:(UIWindow **)outWindow view:(UIView **)outView {
    UIView *view = nil;
    UIWindow *window = [self resolveWindowForEvent:event hitView:&view];
    if (!window) {
        TSLog(@"began %ld at (%.1f, %.1f): no window or view there", (long)event.identifier, event.point.x, event.point.y);
        return nil;
    }
    UITouch *touch = TSCreateTouch(window, view, TSScreenToWindow(window, event.point));
    if (!touch) {
        TSLog(@"began %ld: UITouch private ivars missing", (long)event.identifier);
        return nil;
    }
    TSTouchSetIdentifier(touch, event.identifier);

    TSTouchState *state = [[TSTouchState alloc] init];
    state.identifier = event.identifier;
    state.touch = touch;
    state.window = window;
    state.view = view;
    state.control = TSNearestControl(view);
    state.scrollView = TSNearestScrollView(view);
    state.panGestures = TSFindGestures(view, [UIPanGestureRecognizer class]);
    state.startPoint = event.point;
    state.startContentOffset = state.scrollView ? state.scrollView.contentOffset : CGPointZero;
    _states[@(event.identifier)] = state;

    *outWindow = window;
    *outView = view;
    return state;
}

- (TSTouchState *)continueTouchForEvent:(TSTouchEvent *)event window:(UIWindow **)outWindow view:(UIView **)outView {
    TSTouchState *state = _states[@(event.identifier)];
    if (!state) {
        TSLog(@"action %ld for unknown identifier %ld", (long)event.action, (long)event.identifier);
        return nil;
    }
    UIView *view = nil;
    UIWindow *window = [self continuingWindowForState:state event:event view:&view];
    if (!window) {
        return nil;
    }
    UITouch *touch = state.touch;
    TSTouchSetWindowAndView(touch, window, view);
    TSTouchSetLocation(touch, TSScreenToWindow(window, event.point));
    state.window = window;
    state.view = view;
    if (TSExceedsTapSlop(event.point.x - state.startPoint.x, event.point.y - state.startPoint.y)) {
        state.movedPastTapSlop = YES;
    }
    TSTouchSetTapFlag(touch, !state.movedPastTapSlop);
    switch (event.action) {
        case TSTouchActionMoved:
            TSTouchSetPhase(touch, UITouchPhaseMoved);
            break;
        case TSTouchActionEnded:
            TSTouchSetPhase(touch, UITouchPhaseEnded);
            break;
        default:
            TSTouchSetPhase(touch, UITouchPhaseCancelled);
            break;
    }
    *outWindow = window;
    *outView = view;
    return state;
}

#pragma mark Public entry

- (BOOL)sendEvent:(TSTouchEvent *)event {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self sendEvent:event];
        });
        return YES;
    }
    TSInstallHooks();
    UIWindow *window = nil;
    UIView *view = nil;
    TSTouchState *state = event.action == TSTouchActionBegan
                              ? [self beginTouchForEvent:event window:&window view:&view]
                              : [self continueTouchForEvent:event window:&window view:&view];
    if (!state) {
        return NO;
    }
    [self deliverEvent:event state:state window:window view:view];
    return YES;
}

#pragma mark Delivery chain

// Port of FUN_00584b84.
- (void)deliverEvent:(TSTouchEvent *)event state:(TSTouchState *)state window:(UIWindow *)window view:(UIView *)view {
    TSDeliveryOptions options = self.deliveryOptions;
    UITouch *touch = state.touch;
    TSTouchAction action = event.action;

    UIScrollView *scrollView = state.scrollView;
    CGPoint offsetBeforeDispatch = scrollView ? scrollView.contentOffset : CGPointZero;

    UIControl *control = TSNearestControl(view);
    if (action == TSTouchActionEnded || action == TSTouchActionCancelled) {
        TSTrackControl(control);
    }

    UIEvent *uiEvent = TSCreateEvent(touch);
    BOOL dispatched = NO;
    if (uiEvent && (options & TSDeliverySendEvent)) {
        [self withExcludedViewDisabledInWindow:window perform:^{
            [window sendEvent:uiEvent];
        }];
        dispatched = YES;
    }
    TSLog(@"action %ld id %ld -> %@ event=%@ dispatched=%d", (long)action, (long)event.identifier,
          NSStringFromClass(object_getClass(view)), uiEvent, dispatched);

    // Controls get touches through sendEvent: only. Everything else gets them
    // directly as well, because sendEvent: alone does not reliably reach the view.
    BOOL deliveredDirectly = NO;
    if ((!dispatched || !state.control) && (options & TSDeliveryDirectTouches)) {
        deliveredDirectly = TSDeliverDirect(touch, view, uiEvent);
    }

    CGPoint delta = CGPointMake(event.point.x - state.startPoint.x, event.point.y - state.startPoint.y);
    BOOL pastSlop = TSExceedsTapSlop(delta.x, delta.y);

    if (action == TSTouchActionMoved && !state.control && pastSlop && (options & TSDeliveryScrollViews)) {
        [self driveScrollView:scrollView state:state delta:delta offsetBeforeDispatch:offsetBeforeDispatch dispatched:dispatched];
    }

    // iGameGod only checks pastSlop here, which strands an active pan whose finger
    // ends back near the start. Also running while panActive closes it properly.
    if (action != TSTouchActionBegan && !state.control && (pastSlop || state.panActive) && (options & TSDeliveryPanGestures)) {
        [self drivePanGesturesForState:state action:action delta:delta];
    }

    if (action == TSTouchActionEnded) {
        [self runTapFallbackForTouch:touch view:view control:control deliveredDirectly:deliveredDirectly];
    }
    if (action == TSTouchActionEnded || action == TSTouchActionCancelled) {
        UIControl *tracked = TSTrackedControl();
        if (!tracked || !control || tracked == control) {
            TSTrackControl(nil);
        }
        [_states removeObjectForKey:@(event.identifier)];
    }
}

- (void)driveScrollView:(UIScrollView *)scrollView
                  state:(TSTouchState *)state
                  delta:(CGPoint)delta
   offsetBeforeDispatch:(CGPoint)before
             dispatched:(BOOL)dispatched {
    if (!scrollView || !scrollView.window || !scrollView.scrollEnabled) {
        return;
    }
    CGPoint current = scrollView.contentOffset;
    BOOL scrolledNatively = dispatched && (fabs(current.x - before.x) > kOffsetEpsilon || fabs(current.y - before.y) > kOffsetEpsilon);
    if (scrolledNatively) {
        return;
    }
    double x = state.startContentOffset.x - delta.x;
    double y = state.startContentOffset.y - delta.y;
    UIEdgeInsets inset = scrollView.adjustedContentInset;
    TSClampContentOffset(&x, &y, inset.top, inset.left, inset.bottom, inset.right,
                         scrollView.contentSize.width, scrollView.contentSize.height,
                         CGRectGetWidth(scrollView.bounds), CGRectGetHeight(scrollView.bounds));
    if (fabs(current.x - x) > kOffsetEpsilon || fabs(current.y - y) > kOffsetEpsilon) {
        [scrollView setContentOffset:CGPointMake(x, y) animated:NO];
        [scrollView.panGestureRecognizer setTranslation:delta inView:scrollView];
    }
}

// Port of FUN_0058dda0.
- (void)drivePanGesturesForState:(TSTouchState *)state action:(TSTouchAction)action delta:(CGPoint)delta {
    if (state.panGestures.count == 0) {
        return;
    }
    BOOL wasActive = state.panActive;
    NSInteger gestureState;
    switch (action) {
        case TSTouchActionMoved:
            gestureState = wasActive ? kGestureStateChanged : kGestureStateBegan;
            state.panActive = YES;
            break;
        case TSTouchActionEnded:
            gestureState = wasActive ? kGestureStateEnded : kGestureStateBegan;
            state.panActive = NO;
            break;
        default:
            gestureState = kGestureStateCancelled;
            state.panActive = NO;
            break;
    }
    for (UIPanGestureRecognizer *pan in state.panGestures) {
        if (!pan.enabled) {
            continue;
        }
        [pan setTranslation:delta inView:pan.view];
        TSInvokeGesture(pan, gestureState);
        if (action == TSTouchActionEnded && gestureState == kGestureStateBegan) {
            TSInvokeGesture(pan, kGestureStateEnded);
        }
    }
}

// Port of FUN_00587624: gives an ended touch one way of taking effect if UIKit
// did not already respond to it.
- (void)runTapFallbackForTouch:(UITouch *)touch
                          view:(UIView *)view
                       control:(UIControl *)control
             deliveredDirectly:(BOOL)deliveredDirectly {
    TSDeliveryOptions options = self.deliveryOptions;
    UIView *target = control ?: view;
    if (!target) {
        return;
    }
    NSArray<UITapGestureRecognizer *> *tapGestures = TSFindGestures(target, [UITapGestureRecognizer class]);
    UIView *cell = TSNearestCell(target);
    UIWindow *window = touch.window ?: target.window;

    TSFallbackInputs inputs = {
        .hasControl = control != nil,
        .controlHasTargets = control.allTargets.count > 0,
        .hasTapGestures = tapGestures.count > 0,
        .hasCellAncestor = cell != nil,
        .isKeyWindow = window.isKeyWindow,
        .touchIsTap = TSTouchGetTapFlag(touch),
        .pointInsideTarget = CGRectContainsPoint(target.bounds, [touch locationInView:target]),
        .nativeActionCount = (!TSTrackedControl() || TSTrackedControl() == control) ? TSTrackedActionCount() : 0,
    };
    TSFallback fallback = TSFallbackForInputs(inputs);

    BOOL safeTarget = !deliveredDirectly && TSClassIsSafeTarget(object_getClass(target));
    if (fallback == TSFallbackDirectTap && !safeTarget) {
        return; // Already delivered directly, or not ours to poke at.
    }
    switch (fallback) {
        case TSFallbackControlActions:
            if (options & TSDeliveryControlActions) {
                [self fireControl:control forTouch:touch];
            }
            break;
        case TSFallbackTapGestures: {
            BOOL fired = NO;
            if (options & TSDeliveryTapGestures) {
                for (UITapGestureRecognizer *tap in tapGestures) {
                    fired = TSInvokeGesture(tap, kGestureStateEnded) > 0 || fired;
                }
            }
            if (!fired && safeTarget && (options & TSDeliveryDirectTouches)) {
                [self deliverDirectTapToView:target forTouch:touch];
            }
            break;
        }
        case TSFallbackDirectTap:
            if (options & TSDeliveryDirectTouches) {
                [self deliverDirectTapToView:target forTouch:touch];
            }
            break;
        case TSFallbackCellSelection:
            if (options & TSDeliveryCellSelection) {
                [self selectCell:cell];
            }
            break;
        case TSFallbackNone:
            break;
    }
}

// Port of FUN_0058fa48. TouchUpInside first; the others only if it did nothing.
- (void)fireControl:(UIControl *)control forTouch:(UITouch *)touch {
    if (!CGRectContainsPoint(control.bounds, [touch locationInView:control])) {
        return;
    }
    [control sendActionsForControlEvents:UIControlEventTouchUpInside];
    if (TSTrackedControl() != control || TSTrackedActionCount() == 0) {
        [control sendActionsForControlEvents:UIControlEventValueChanged];
    }
    if (TSTrackedControl() != control || TSTrackedActionCount() == 0) {
        [control sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
    }
}

// Port of FUN_0058fe74: a complete began/ended pair at the touch's location.
- (void)deliverDirectTapToView:(UIView *)view forTouch:(UITouch *)original {
    UIWindow *window = original.window ?: view.window;
    if (!window || !CGRectContainsPoint(view.bounds, [original locationInView:view])) {
        return;
    }
    CGPoint point = [original locationInView:window];
    UITouch *touch = TSCreateTouch(window, view, point);
    if (!touch) {
        return;
    }
    TSTouchSetIdentifier(touch, TSTouchGetIdentifier(original));
    TSTouchSetTapFlag(touch, YES);
    TSTouchSetPhase(touch, UITouchPhaseBegan);
    [view touchesBegan:TSTouchSet(touch) withEvent:TSCreateEvent(touch)];
    TSTouchSetLocation(touch, point);
    TSTouchSetPhase(touch, UITouchPhaseEnded);
    [view touchesEnded:TSTouchSet(touch) withEvent:TSCreateEvent(touch)];
}

// Ports of FUN_00590220 and FUN_00590528, public API paths only.
- (void)selectCell:(UIView *)cell {
    for (UIView *ancestor = cell.superview; ancestor; ancestor = ancestor.superview) {
        if ([ancestor isKindOfClass:[UICollectionView class]] && [cell isKindOfClass:[UICollectionViewCell class]]) {
            UICollectionView *collection = (UICollectionView *)ancestor;
            NSIndexPath *path = [collection indexPathForCell:(UICollectionViewCell *)cell];
            if (!path || !collection.allowsSelection) {
                return;
            }
            id<UICollectionViewDelegate> delegate = collection.delegate;
            if ([delegate respondsToSelector:@selector(collectionView:shouldSelectItemAtIndexPath:)] &&
                ![delegate collectionView:collection shouldSelectItemAtIndexPath:path]) {
                return;
            }
            [collection selectItemAtIndexPath:path animated:NO scrollPosition:UICollectionViewScrollPositionNone];
            if ([delegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) {
                [delegate collectionView:collection didSelectItemAtIndexPath:path];
            }
            return;
        }
        if ([ancestor isKindOfClass:[UITableView class]] && [cell isKindOfClass:[UITableViewCell class]]) {
            UITableView *table = (UITableView *)ancestor;
            NSIndexPath *path = [table indexPathForCell:(UITableViewCell *)cell];
            if (!path || !table.allowsSelection) {
                return;
            }
            [table selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionNone];
            id<UITableViewDelegate> delegate = table.delegate;
            if ([delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
                [delegate tableView:table didSelectRowAtIndexPath:path];
            }
            return;
        }
    }
}

#pragma mark Cancel

// Port of FUN_0058442c.
- (void)cancelAllTouches {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self cancelAllTouches];
        });
        return;
    }
    _sequenceGeneration++;
    NSArray<TSTouchState *> *states = _states.allValues;
    for (TSTouchState *state in states) {
        UIWindow *window = state.touch.window ?: state.window;
        UIView *view = state.view;
        if (!window || !view) {
            continue;
        }
        UITouch *touch = state.touch;
        TSTouchSetPhase(touch, UITouchPhaseCancelled);
        if (state.panActive && (self.deliveryOptions & TSDeliveryPanGestures)) {
            CGPoint location = [touch locationInView:window];
            CGPoint screenPoint = [window.coordinateSpace convertPoint:location toCoordinateSpace:window.screen.coordinateSpace];
            [self drivePanGesturesForState:state action:TSTouchActionCancelled
                                     delta:CGPointMake(screenPoint.x - state.startPoint.x, screenPoint.y - state.startPoint.y)];
        }
        UIEvent *event = TSCreateEvent(touch);
        if (event && (self.deliveryOptions & TSDeliverySendEvent)) {
            [self withExcludedViewDisabledInWindow:window perform:^{
                [window sendEvent:event];
            }];
        }
        if (self.deliveryOptions & TSDeliveryDirectTouches) {
            TSDeliverDirect(touch, view, event);
        }
    }
    TSTrackControl(nil);
    [_states removeAllObjects];
}

#pragma mark Convenience

- (BOOL)touchDownWithIdentifier:(NSInteger)identifier atPoint:(CGPoint)point {
    return [self sendEvent:[TSTouchEvent eventWithIdentifier:identifier action:TSTouchActionBegan point:point]];
}

- (BOOL)touchMoveWithIdentifier:(NSInteger)identifier toPoint:(CGPoint)point {
    return [self sendEvent:[TSTouchEvent eventWithIdentifier:identifier action:TSTouchActionMoved point:point]];
}

- (BOOL)touchUpWithIdentifier:(NSInteger)identifier atPoint:(CGPoint)point {
    return [self sendEvent:[TSTouchEvent eventWithIdentifier:identifier action:TSTouchActionEnded point:point]];
}

- (BOOL)touchCancelWithIdentifier:(NSInteger)identifier atPoint:(CGPoint)point {
    return [self sendEvent:[TSTouchEvent eventWithIdentifier:identifier action:TSTouchActionCancelled point:point]];
}

- (void)tapAtPoint:(CGPoint)point {
    [self tapAtPoint:point duration:kDefaultTapDuration completion:nil];
}

- (void)tapAtPoint:(CGPoint)point duration:(NSTimeInterval)duration completion:(void (^)(BOOL))completion {
    [self swipeFromPoint:point toPoint:point duration:duration completion:completion];
}

- (void)swipeFromPoint:(CGPoint)from toPoint:(CGPoint)to duration:(NSTimeInterval)duration completion:(void (^)(BOOL))completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger identifier = self->_nextIdentifier++;
        NSUInteger generation = self->_sequenceGeneration;
        if (![self touchDownWithIdentifier:identifier atPoint:from]) {
            if (completion) {
                completion(NO);
            }
            return;
        }
        BOOL stationary = CGPointEqualToPoint(from, to);
        NSInteger steps = stationary ? 1 : MAX((NSInteger)ceil(duration / kSwipeStepInterval), 1);
        [self runStep:1 of:steps identifier:identifier from:from to:to
             interval:duration / steps generation:generation completion:completion];
    });
}

- (void)runStep:(NSInteger)step
             of:(NSInteger)steps
     identifier:(NSInteger)identifier
           from:(CGPoint)from
             to:(CGPoint)to
       interval:(NSTimeInterval)interval
     generation:(NSUInteger)generation
     completion:(void (^)(BOOL))completion {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != self->_sequenceGeneration) {
            if (completion) {
                completion(NO);
            }
            return;
        }
        CGFloat progress = (CGFloat)step / steps;
        CGPoint point = CGPointMake(from.x + (to.x - from.x) * progress, from.y + (to.y - from.y) * progress);
        if (step < steps) {
            [self touchMoveWithIdentifier:identifier toPoint:point];
            [self runStep:step + 1 of:steps identifier:identifier from:from to:to
                 interval:interval generation:generation completion:completion];
            return;
        }
        if (!CGPointEqualToPoint(from, to)) {
            [self touchMoveWithIdentifier:identifier toPoint:point];
        }
        BOOL finished = [self touchUpWithIdentifier:identifier atPoint:point];
        if (completion) {
            completion(finished);
        }
    });
}

@end

#pragma mark - C interface

bool TSTouchDown(long identifier, double x, double y) {
    return [TSTouchSynthesizer.sharedSynthesizer touchDownWithIdentifier:identifier atPoint:CGPointMake(x, y)];
}

bool TSTouchMove(long identifier, double x, double y) {
    return [TSTouchSynthesizer.sharedSynthesizer touchMoveWithIdentifier:identifier toPoint:CGPointMake(x, y)];
}

bool TSTouchUp(long identifier, double x, double y) {
    return [TSTouchSynthesizer.sharedSynthesizer touchUpWithIdentifier:identifier atPoint:CGPointMake(x, y)];
}

bool TSTouchCancel(long identifier, double x, double y) {
    return [TSTouchSynthesizer.sharedSynthesizer touchCancelWithIdentifier:identifier atPoint:CGPointMake(x, y)];
}

void TSTouchCancelAll(void) {
    [TSTouchSynthesizer.sharedSynthesizer cancelAllTouches];
}

void TSTap(double x, double y) {
    [TSTouchSynthesizer.sharedSynthesizer tapAtPoint:CGPointMake(x, y)];
}

void TSSwipe(double fromX, double fromY, double toX, double toY, double duration) {
    [TSTouchSynthesizer.sharedSynthesizer swipeFromPoint:CGPointMake(fromX, fromY)
                                                 toPoint:CGPointMake(toX, toY)
                                                duration:duration
                                              completion:nil];
}
