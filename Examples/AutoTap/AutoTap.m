// AutoTap: an injectable auto clicker built on TouchSynth.
//
// A constructor adds a floating button in its own overlay window. From its panel
// you record tap points and swipes on screen, set the delays and swipe time, and
// start a loop that replays them into the app with synthesized touches.
//
// The overlay is TouchSynth's excludedView, so synthesized touches always land in
// the app's own windows, even under the markers or the panel.
#import <UIKit/UIKit.h>
#import <math.h>

#import "ATSession.h"
#import "ATViews.h"
#import "TouchSynth.h"

static const CGFloat kTapMarkerSize = 46;
static const CGFloat kSwipeEndMarkerSize = 26;
static const CGFloat kSwipeMinimumDistance = 12;
static const CGFloat kPanelMaxWidth = 340;

static UIWindowScene *ATActiveWindowScene(void) {
    UIWindowScene *fallback = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            return (UIWindowScene *)scene;
        }
        fallback = fallback ?: (UIWindowScene *)scene;
    }
    return fallback;
}

static CGFloat ATDistance(CGPoint a, CGPoint b) {
    return hypot(b.x - a.x, b.y - a.y);
}

// A line with an arrowhead at `to`, for swipe markers and previews.
static UIBezierPath *ATArrowPath(CGPoint from, CGPoint to) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:from];
    [path addLineToPoint:to];
    CGFloat angle = atan2(to.y - from.y, to.x - from.x);
    CGFloat length = 16;
    for (int side = -1; side <= 1; side += 2) {
        CGFloat wing = angle + M_PI + side * M_PI / 7;
        [path moveToPoint:to];
        [path addLineToPoint:CGPointMake(to.x + length * cos(wing), to.y + length * sin(wing))];
    }
    return path;
}

static CAShapeLayer *ATArrowLayer(UIColor *color) {
    CAShapeLayer *layer = [CAShapeLayer layer];
    layer.strokeColor = color.CGColor;
    layer.fillColor = [UIColor clearColor].CGColor;
    layer.lineWidth = 3.5;
    layer.lineCap = kCALineCapRound;
    layer.lineJoin = kCALineJoinRound;
    layer.lineDashPattern = @[@10, @7];
    layer.shadowColor = [UIColor blackColor].CGColor;
    layer.shadowOpacity = 0.4;
    layer.shadowRadius = 3;
    layer.shadowOffset = CGSizeZero;
    return layer;
}

#pragma mark - Recorder

// Full-screen capture layer: a tap adds a tap step, a drag adds a swipe step.
@interface ATRecordView : UIView
@property (nonatomic, copy, nullable) void (^onTap)(CGPoint point);
@property (nonatomic, copy, nullable) void (^onSwipe)(CGPoint from, CGPoint to);
@property (nonatomic, copy, nullable) void (^onDone)(void);
@end

@implementation ATRecordView {
    UIView *_hint;
    UITouch *_tracking;
    CGPoint _start;
    CAShapeLayer *_preview;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
        self.multipleTouchEnabled = NO;
        _preview = ATArrowLayer(ATSwipeColor());
        [self.layer addSublayer:_preview];
        [self buildHint];
    }
    return self;
}

- (void)buildHint {
    UIVisualEffectView *pill = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    pill.layer.cornerRadius = 22;
    pill.layer.cornerCurve = kCACornerCurveContinuous;
    pill.clipsToBounds = YES;
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    pill.contentView.backgroundColor = ATSurfaceColor();
    pill.layer.borderWidth = 1;
    pill.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.16].CGColor;

    UIImageView *dot = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"record.circle.fill"]];
    dot.tintColor = ATStopColor();
    UILabel *text = [[UILabel alloc] init];
    text.numberOfLines = 2;
    text.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    text.textColor = [UIColor whiteColor];
    text.text = @"Tap to add a tap\nDrag to add a swipe";
    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    [done setTitle:@"Done" forState:UIControlStateNormal];
    done.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    [done setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    done.backgroundColor = ATGoColor();
    done.layer.cornerRadius = 15;
    done.contentEdgeInsets = UIEdgeInsetsMake(6, 16, 6, 16);
    [done addTarget:self action:@selector(doneTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[dot, text, done]];
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 10;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [pill.contentView addSubview:row];
    [self addSubview:pill];
    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:pill.contentView.topAnchor constant:7],
        [row.bottomAnchor constraintEqualToAnchor:pill.contentView.bottomAnchor constant:-7],
        [row.leadingAnchor constraintEqualToAnchor:pill.contentView.leadingAnchor constant:14],
        [row.trailingAnchor constraintEqualToAnchor:pill.contentView.trailingAnchor constant:-7],
        [pill.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [pill.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:12],
    ]];
    // The hint may cover the spot you want, so it can be dragged out of the way.
    [pill addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(hintDragged:)]];
    _hint = pill;
}

- (void)hintDragged:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self];
    _hint.transform = CGAffineTransformTranslate(_hint.transform, translation.x, translation.y);
    [pan setTranslation:CGPointZero inView:self];
}

- (void)doneTapped {
    if (self.onDone) {
        self.onDone();
    }
}

- (BOOL)touchIsOnHint:(UITouch *)touch {
    return CGRectContainsPoint(_hint.frame, [touch locationInView:self]);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = touches.anyObject;
    if (_tracking || [self touchIsOnHint:touch]) {
        return;
    }
    _tracking = touch;
    _start = [touch locationInView:self];
    _preview.path = nil;
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (![touches containsObject:_tracking]) {
        return;
    }
    CGPoint point = [_tracking locationInView:self];
    _preview.path = ATDistance(_start, point) > kSwipeMinimumDistance ? ATArrowPath(_start, point).CGPath : nil;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (![touches containsObject:_tracking]) {
        return;
    }
    CGPoint end = [_tracking locationInView:self];
    _tracking = nil;
    _preview.path = nil;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    if (ATDistance(_start, end) > kSwipeMinimumDistance) {
        if (self.onSwipe) {
            self.onSwipe(_start, end);
        }
    } else if (self.onTap) {
        self.onTap(_start);
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if ([touches containsObject:_tracking]) {
        _tracking = nil;
        _preview.path = nil;
    }
}

@end

#pragma mark - Overlay

@interface ATOverlayWindow : UIWindow
@end

@implementation ATOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
- (BOOL)canBecomeKeyWindow {
    return NO;
}
@end

@interface ATOverlayViewController : UIViewController
@end

@implementation ATOverlayViewController {
    ATSession *_session;
    ATPassthroughView *_markerLayer;
    UIView *_effectLayer;
    ATRecordView *_recordView;
    ATPanelView *_panel;
    ATBubbleView *_bubble;
    NSMutableArray<ATMarkerView *> *_markers;      // start marker of each step, by index
    NSMutableArray<ATMarkerView *> *_extraMarkers; // swipe end handles
    NSMutableArray<CAShapeLayer *> *_arrows;       // one per step, by index; hidden for taps
    BOOL _bubblePlaced;
    CGSize _lastSize;
}

- (void)loadView {
    self.view = [[ATPassthroughView alloc] init];
    self.view.backgroundColor = [UIColor clearColor];
}

// The app's own root view controller decides status bar and rotation behaviour.
- (UIViewController *)appRootViewController {
    for (UIWindow *window in self.view.window.windowScene.windows) {
        if (window != self.view.window && window.isKeyWindow) {
            return window.rootViewController;
        }
    }
    return nil;
}

- (BOOL)prefersStatusBarHidden {
    UIViewController *root = [self appRootViewController];
    return root ? root.prefersStatusBarHidden : [super prefersStatusBarHidden];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    UIViewController *root = [self appRootViewController];
    return root ? root.preferredStatusBarStyle : UIStatusBarStyleLightContent;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    UIViewController *root = [self appRootViewController];
    return root ? root.supportedInterfaceOrientations : UIInterfaceOrientationMaskAll;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return [self appRootViewController].prefersHomeIndicatorAutoHidden;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _session = ATSession.shared;
    _markers = [NSMutableArray array];
    _extraMarkers = [NSMutableArray array];
    _arrows = [NSMutableArray array];
    TSTouchSynthesizer.sharedSynthesizer.excludedView = self.view;

    _markerLayer = [[ATPassthroughView alloc] initWithFrame:self.view.bounds];
    _markerLayer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_markerLayer];

    _effectLayer = [[UIView alloc] initWithFrame:self.view.bounds];
    _effectLayer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _effectLayer.userInteractionEnabled = NO;
    [self.view addSubview:_effectLayer];

    _recordView = [[ATRecordView alloc] initWithFrame:self.view.bounds];
    _recordView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _recordView.hidden = YES;
    [self.view addSubview:_recordView];

    _panel = [[ATPanelView alloc] initWithSession:_session];
    _panel.translatesAutoresizingMaskIntoConstraints = NO;
    _panel.hidden = YES;
    [self.view addSubview:_panel];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    NSLayoutConstraint *preferredWidth = [_panel.widthAnchor constraintEqualToConstant:kPanelMaxWidth];
    preferredWidth.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [_panel.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [_panel.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        preferredWidth,
        [_panel.widthAnchor constraintLessThanOrEqualToAnchor:safe.widthAnchor constant:-24],
        [_panel.heightAnchor constraintLessThanOrEqualToAnchor:safe.heightAnchor constant:-24],
    ]];

    _bubble = [[ATBubbleView alloc] init];
    [self.view addSubview:_bubble];

    [self wireCallbacks];
    [self rebuildMarkers];
}

- (void)wireCallbacks {
    __weak ATOverlayViewController *weakSelf = self;
    _bubble.onTap = ^{ [weakSelf bubbleTapped]; };
    _bubble.onMoved = ^(CGPoint center) { ATSession.shared.bubbleCenter = center; };

    _panel.onClose = ^{ [weakSelf setPanelVisible:NO]; };
    _panel.onRecord = ^{ [weakSelf setRecording:YES]; };
    _panel.onToggleRun = ^{ [weakSelf toggleRun]; };

    _recordView.onTap = ^(CGPoint point) {
        ATOverlayViewController *strongSelf = weakSelf;
        [strongSelf->_session addAction:[ATAction tapAt:[strongSelf screenPointFromView:point]]];
    };
    _recordView.onSwipe = ^(CGPoint from, CGPoint to) {
        ATOverlayViewController *strongSelf = weakSelf;
        [strongSelf->_session addAction:[ATAction swipeFrom:[strongSelf screenPointFromView:from]
                                                         to:[strongSelf screenPointFromView:to]]];
    };
    _recordView.onDone = ^{ [weakSelf setRecording:NO]; };

    _session.onChange = ^{
        ATOverlayViewController *strongSelf = weakSelf;
        [strongSelf rebuildMarkers];
        [strongSelf->_panel reloadSteps];
    };
    _session.onRunStateChange = ^{ [weakSelf runStateChanged]; };
    _session.onStepStart = ^(NSInteger index, ATAction *action) { [weakSelf stepStarted:index action:action]; };
    _session.onStepFinish = ^(NSInteger index, ATAction *action, BOOL reachedTarget) {
        if (!reachedTarget) {
            [weakSelf showMissAt:action.type == ATActionTypeSwipe ? action.end : action.start];
        }
    };
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    if (size.width <= 0) {
        return;
    }
    if (!_bubblePlaced) {
        _bubblePlaced = YES;
        CGPoint saved = _session.bubbleCenter;
        UIEdgeInsets insets = self.view.safeAreaInsets;
        _bubble.center = CGPointEqualToPoint(saved, CGPointZero)
            ? CGPointMake(size.width - insets.right - 40, insets.top + size.height * 0.3)
            : saved;
    }
    if (!CGSizeEqualToSize(size, _lastSize)) {
        _lastSize = size;
        CGRect area = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
        _bubble.center = CGPointMake(MIN(MAX(_bubble.center.x, CGRectGetMinX(area) + 39), CGRectGetMaxX(area) - 39),
                                     MIN(MAX(_bubble.center.y, CGRectGetMinY(area) + 39), CGRectGetMaxY(area) - 39));
        [self rebuildMarkers];
    }
}

#pragma mark Coordinates

- (CGPoint)screenPointFromView:(CGPoint)point {
    UIScreen *screen = self.view.window.screen ?: [UIScreen mainScreen];
    return [self.view convertPoint:point toCoordinateSpace:screen.coordinateSpace];
}

- (CGPoint)viewPointFromScreen:(CGPoint)point {
    UIScreen *screen = self.view.window.screen ?: [UIScreen mainScreen];
    return [screen.coordinateSpace convertPoint:point toCoordinateSpace:self.view];
}

#pragma mark Modes

- (void)bubbleTapped {
    if (_session.running) {
        [_session stop];
        [self setPanelVisible:YES];
    } else if (!_recordView.hidden) {
        [self setRecording:NO];
    } else {
        [self setPanelVisible:_panel.hidden];
    }
}

- (void)setPanelVisible:(BOOL)visible {
    if (visible == !_panel.hidden) {
        return;
    }
    if (visible) {
        [_panel reloadSteps];
        _panel.hidden = NO;
        _panel.alpha = 0;
        _panel.transform = CGAffineTransformMakeScale(0.9, 0.9);
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0 animations:^{
            self->_panel.alpha = 1;
            self->_panel.transform = CGAffineTransformIdentity;
        } completion:nil];
    } else {
        [UIView animateWithDuration:0.2 animations:^{
            self->_panel.alpha = 0;
            self->_panel.transform = CGAffineTransformMakeScale(0.92, 0.92);
        } completion:^(BOOL finished) {
            if (self->_panel.alpha == 0) {
                self->_panel.hidden = YES;
                self->_panel.transform = CGAffineTransformIdentity;
            }
        }];
    }
}

- (void)setRecording:(BOOL)recording {
    [_session stop];
    if (recording) {
        [self setPanelVisible:NO];
    }
    _recordView.hidden = NO;
    [UIView animateWithDuration:0.2 animations:^{
        self->_recordView.alpha = recording ? 1 : 0;
    } completion:^(BOOL finished) {
        self->_recordView.hidden = !recording;
    }];
    if (!recording) {
        [self setPanelVisible:YES];
    }
}

- (void)toggleRun {
    if (_session.running) {
        [_session stop];
        return;
    }
    if (_session.actions.count == 0) {
        [_panel showMessage:@"Record at least one step first"];
        return;
    }
    [self setPanelVisible:NO];
    // Let the panel's fade finish so the first touch isn't mid-animation.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self->_session start];
    });
}

- (void)runStateChanged {
    BOOL running = _session.running;
    _bubble.running = running;
    [_panel updateRunState];
    for (ATMarkerView *marker in [_markers arrayByAddingObjectsFromArray:_extraMarkers]) {
        marker.userInteractionEnabled = !running; // never block touches while running
        marker.active = NO;
    }
    [UIView animateWithDuration:0.25 animations:^{
        self->_markerLayer.alpha = running ? 0.85 : 1;
    }];
}

#pragma mark Markers

- (void)rebuildMarkers {
    for (UIView *marker in [_markers arrayByAddingObjectsFromArray:_extraMarkers]) {
        [marker removeFromSuperview];
    }
    for (CAShapeLayer *arrow in _arrows) {
        [arrow removeFromSuperlayer];
    }
    [_markers removeAllObjects];
    [_extraMarkers removeAllObjects];
    [_arrows removeAllObjects];

    NSArray<ATAction *> *actions = _session.actions;
    __weak ATOverlayViewController *weakSelf = self;
    for (NSInteger i = 0; i < (NSInteger)actions.count; i++) {
        ATAction *action = actions[i];
        BOOL swipe = action.type == ATActionTypeSwipe;
        UIColor *color = swipe ? ATSwipeColor() : ATTapColor();

        CAShapeLayer *arrow = ATArrowLayer(color);
        arrow.hidden = !swipe;
        [_markerLayer.layer addSublayer:arrow];
        [_arrows addObject:arrow];

        ATMarkerView *startMarker = [[ATMarkerView alloc] initWithNumber:i + 1 color:color diameter:kTapMarkerSize];
        startMarker.center = [self viewPointFromScreen:action.start];
        startMarker.onDrag = ^(ATMarkerView *marker, BOOL finished) {
            action.start = [weakSelf screenPointFromView:marker.center];
            if (action.type == ATActionTypeTap) {
                action.end = action.start;
            }
            [weakSelf markerMoved:finished];
        };
        [_markers addObject:startMarker];

        if (swipe) {
            ATMarkerView *endMarker = [[ATMarkerView alloc] initWithNumber:0 color:color diameter:kSwipeEndMarkerSize];
            endMarker.center = [self viewPointFromScreen:action.end];
            endMarker.onDrag = ^(ATMarkerView *marker, BOOL finished) {
                action.end = [weakSelf screenPointFromView:marker.center];
                [weakSelf markerMoved:finished];
            };
            [_extraMarkers addObject:endMarker];
            [_markerLayer addSubview:endMarker];
        }
    }
    // Start markers on top so numbered handles are always grabbable.
    for (ATMarkerView *marker in _markers) {
        [_markerLayer addSubview:marker];
        marker.userInteractionEnabled = !_session.running;
    }
    for (UIView *marker in _extraMarkers) {
        marker.userInteractionEnabled = !_session.running;
    }
    [self redrawArrows];
}

- (void)redrawArrows {
    NSArray<ATAction *> *actions = _session.actions;
    for (NSUInteger i = 0; i < actions.count && i < _arrows.count; i++) {
        ATAction *action = actions[i];
        if (action.type == ATActionTypeSwipe) {
            _arrows[i].path = ATArrowPath([self viewPointFromScreen:action.start], [self viewPointFromScreen:action.end]).CGPath;
        }
    }
}

- (void)markerMoved:(BOOL)finished {
    [self redrawArrows];
    if (finished) {
        // Rebuilding replaces the marker whose gesture is finishing, so wait a turn.
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_session actionsDidChange];
        });
    }
}

#pragma mark Touch effects

- (void)stepStarted:(NSInteger)index action:(ATAction *)action {
    [_panel highlightStep:index];
    for (NSInteger i = 0; i < (NSInteger)_markers.count; i++) {
        _markers[i].active = i == index;
    }
    if (!_session.showTouches) {
        return;
    }
    CGPoint start = [self viewPointFromScreen:action.start];
    if (action.type == ATActionTypeSwipe) {
        [self showTrailFrom:start to:[self viewPointFromScreen:action.end] duration:_session.swipeDuration];
    } else {
        [self showRippleAt:start color:ATTapColor()];
    }
}

- (void)addTemporaryLayer:(CALayer *)layer animations:(NSArray<CAAnimation *> *)animations duration:(CFTimeInterval)duration {
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.animations = animations;
    group.duration = duration;
    group.fillMode = kCAFillModeForwards;
    group.removedOnCompletion = NO;
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        [layer removeFromSuperlayer];
    }];
    [_effectLayer.layer addSublayer:layer];
    [layer addAnimation:group forKey:@"effect"];
    [CATransaction commit];
}

- (CAShapeLayer *)circleAt:(CGPoint)center radius:(CGFloat)radius {
    CAShapeLayer *circle = [CAShapeLayer layer];
    circle.bounds = CGRectMake(0, 0, radius * 2, radius * 2);
    circle.position = center;
    circle.path = [UIBezierPath bezierPathWithOvalInRect:circle.bounds].CGPath;
    return circle;
}

- (void)showRippleAt:(CGPoint)point color:(UIColor *)color {
    CAShapeLayer *ring = [self circleAt:point radius:30];
    ring.fillColor = [UIColor clearColor].CGColor;
    ring.strokeColor = color.CGColor;
    ring.lineWidth = 3;
    CABasicAnimation *grow = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    grow.fromValue = @0.3;
    grow.toValue = @1.6;
    grow.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @1;
    fade.toValue = @0;
    [self addTemporaryLayer:ring animations:@[grow, fade] duration:0.55];

    CAShapeLayer *dot = [self circleAt:point radius:16];
    dot.fillColor = [color colorWithAlphaComponent:0.85].CGColor;
    dot.strokeColor = [UIColor whiteColor].CGColor;
    dot.lineWidth = 2;
    CABasicAnimation *shrink = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    shrink.fromValue = @1.1;
    shrink.toValue = @0.5;
    CABasicAnimation *dotFade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    dotFade.fromValue = @1;
    dotFade.toValue = @0;
    [self addTemporaryLayer:dot animations:@[shrink, dotFade] duration:0.4];
}

- (void)showTrailFrom:(CGPoint)from to:(CGPoint)to duration:(NSTimeInterval)duration {
    UIColor *color = ATSwipeColor();
    CAShapeLayer *trail = [CAShapeLayer layer];
    UIBezierPath *line = [UIBezierPath bezierPath];
    [line moveToPoint:from];
    [line addLineToPoint:to];
    trail.path = line.CGPath;
    trail.strokeColor = [color colorWithAlphaComponent:0.9].CGColor;
    trail.lineWidth = 10;
    trail.lineCap = kCALineCapRound;
    trail.fillColor = [UIColor clearColor].CGColor;
    CABasicAnimation *draw = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    draw.fromValue = @0;
    draw.toValue = @1;
    draw.duration = duration;
    CABasicAnimation *erase = [CABasicAnimation animationWithKeyPath:@"strokeStart"];
    erase.fromValue = @0;
    erase.toValue = @1;
    erase.beginTime = duration * 0.4;
    erase.duration = duration * 0.6 + 0.25;
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @1;
    fade.toValue = @0;
    fade.beginTime = duration;
    fade.duration = 0.25;
    [self addTemporaryLayer:trail animations:@[draw, erase, fade] duration:duration + 0.25];

    CAShapeLayer *finger = [self circleAt:from radius:16];
    finger.fillColor = [color colorWithAlphaComponent:0.9].CGColor;
    finger.strokeColor = [UIColor whiteColor].CGColor;
    finger.lineWidth = 2;
    CABasicAnimation *move = [CABasicAnimation animationWithKeyPath:@"position"];
    move.fromValue = [NSValue valueWithCGPoint:from];
    move.toValue = [NSValue valueWithCGPoint:to];
    move.duration = duration;
    move.fillMode = kCAFillModeForwards;
    CABasicAnimation *lift = [CABasicAnimation animationWithKeyPath:@"opacity"];
    lift.fromValue = @1;
    lift.toValue = @0;
    lift.beginTime = duration;
    lift.duration = 0.2;
    [self addTemporaryLayer:finger animations:@[move, lift] duration:duration + 0.2];
}

// Nothing in the app was under the point.
- (void)showMissAt:(CGPoint)screenPoint {
    if (_session.showTouches) {
        [self showRippleAt:[self viewPointFromScreen:screenPoint] color:ATStopColor()];
    }
}

@end

#pragma mark - Entry point

static UIWindow *sOverlayWindow;

// Scene-based apps attach the window to a scene, which can connect a moment after
// the app becomes active. Apps without a scene manifest never get one.
static void ATInstallOverlay(int sceneRetriesLeft) {
    if (sOverlayWindow) {
        return;
    }
    UIWindowScene *scene = ATActiveWindowScene();
    if (!scene && sceneRetriesLeft > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            ATInstallOverlay(sceneRetriesLeft - 1);
        });
        return;
    }
    ATOverlayWindow *window = scene ? [[ATOverlayWindow alloc] initWithWindowScene:scene]
                                    : [[ATOverlayWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    window.windowLevel = UIWindowLevelAlert + 1;
    window.backgroundColor = [UIColor clearColor];
    window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    window.rootViewController = [[ATOverlayViewController alloc] init];
    window.hidden = NO;
    sOverlayWindow = window;
}

__attribute__((constructor))
static void ATAutoTapInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
            ATInstallOverlay(3);
            return;
        }
        __block id token = [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                        [[NSNotificationCenter defaultCenter] removeObserver:token];
                        ATInstallOverlay(3);
                    }];
    });
}
