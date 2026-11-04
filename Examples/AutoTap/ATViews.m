#import "ATViews.h"

#import <math.h>

static const CGFloat kBubbleSize = 58;
static const CGFloat kEdgeMargin = 10;
static const CGFloat kStepRowHeight = 50;
static const CGFloat kVisibleStepRows = 3.5;

// Slider position 0...1 maps exponentially onto seconds, for fine control at the low end.
static const NSTimeInterval kMinDelay = 0.05, kMaxDelay = 10;
static const NSTimeInterval kMinSwipeTime = 0.05, kMaxSwipeTime = 3;

static NSInteger const kLoopValues[] = {0, 1, 2, 3, 5, 10, 25, 50, 100, 250, 500, 1000};

UIColor *ATTapColor(void) { return [UIColor colorWithRed:0.30 green:0.58 blue:1.00 alpha:1]; }
UIColor *ATSwipeColor(void) { return [UIColor colorWithRed:1.00 green:0.62 blue:0.22 alpha:1]; }
UIColor *ATGoColor(void) { return [UIColor colorWithRed:0.20 green:0.80 blue:0.45 alpha:1]; }
UIColor *ATStopColor(void) { return [UIColor colorWithRed:1.00 green:0.32 blue:0.32 alpha:1]; }

static UIImage *ATSymbol(NSString *name, CGFloat size, UIFontWeight weight) {
    UIImageSymbolWeight symbolWeight = weight >= UIFontWeightBold ? UIImageSymbolWeightBold : UIImageSymbolWeightSemibold;
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:size weight:symbolWeight];
    return [UIImage systemImageNamed:name withConfiguration:config];
}

static float ATSliderValue(NSTimeInterval seconds, NSTimeInterval min, NSTimeInterval max) {
    return (float)(log(MAX(seconds, min) / min) / log(max / min));
}

static NSTimeInterval ATSeconds(float value, NSTimeInterval min, NSTimeInterval max) {
    NSTimeInterval seconds = min * pow(max / min, value);
    return seconds < 1 ? round(seconds * 100) / 100 : round(seconds * 10) / 10;
}

static NSString *ATFormatSeconds(NSTimeInterval seconds) {
    if (seconds < 1) {
        return [NSString stringWithFormat:@"%.0f ms", seconds * 1000];
    }
    return [NSString stringWithFormat:@"%.1f s", seconds];
}

static NSString *ATFormatLoops(NSInteger loops) {
    return loops == 0 ? @"∞" : [NSString stringWithFormat:@"%ld×", (long)loops];
}

#pragma mark - Passthrough

@implementation ATPassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

#pragma mark - Bubble

@implementation ATBubbleView {
    UIVisualEffectView *_blur;
    UIView *_tint;
    UIImageView *_icon;
    CAShapeLayer *_ring;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:CGRectMake(0, 0, kBubbleSize, kBubbleSize)])) {
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.35;
        self.layer.shadowRadius = 10;
        self.layer.shadowOffset = CGSizeMake(0, 4);

        _blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
        _blur.frame = self.bounds;
        _blur.layer.cornerRadius = kBubbleSize / 2;
        _blur.clipsToBounds = YES;
        _blur.userInteractionEnabled = NO;
        [self addSubview:_blur];

        _tint = [[UIView alloc] initWithFrame:self.bounds];
        _tint.layer.cornerRadius = kBubbleSize / 2;
        _tint.userInteractionEnabled = NO;
        [self addSubview:_tint];

        _icon = [[UIImageView alloc] initWithFrame:CGRectInset(self.bounds, 15, 15)];
        _icon.contentMode = UIViewContentModeScaleAspectFit;
        _icon.tintColor = [UIColor whiteColor];
        [self addSubview:_icon];

        _ring = [CAShapeLayer layer];
        _ring.frame = self.bounds;
        _ring.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(self.bounds, 2, 2)].CGPath;
        _ring.fillColor = [UIColor clearColor].CGColor;
        _ring.lineWidth = 3;
        _ring.lineCap = kCALineCapRound;
        _ring.strokeEnd = 0.28;
        [self.layer addSublayer:_ring];

        [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
        [self addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragged:)]];
        [self applyRunning:NO];
    }
    return self;
}

- (void)setRunning:(BOOL)running {
    if (_running != running) {
        _running = running;
        [self applyRunning:running];
    }
}

- (void)applyRunning:(BOOL)running {
    _icon.image = ATSymbol(running ? @"stop.fill" : @"hand.tap.fill", 22, UIFontWeightBold);
    _tint.backgroundColor = running ? [ATStopColor() colorWithAlphaComponent:0.55] : [ATTapColor() colorWithAlphaComponent:0.35];
    _ring.strokeColor = ATGoColor().CGColor;
    _ring.hidden = !running;
    [_ring removeAllAnimations];
    if (running) {
        CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        spin.fromValue = @0;
        spin.toValue = @(2 * M_PI);
        spin.duration = 1.0;
        spin.repeatCount = HUGE_VALF;
        [_ring addAnimation:spin forKey:@"spin"];
    }
}

- (void)tapped {
    [UIView animateWithDuration:0.08 animations:^{
        self.transform = CGAffineTransformMakeScale(0.88, 0.88);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:0 options:0 animations:^{
            self.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];
    if (self.onTap) {
        self.onTap();
    }
}

- (void)dragged:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self.superview];
    self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:self.superview];
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        CGPoint target = [self snappedCenter];
        [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0 options:0 animations:^{
            self.center = target;
        } completion:nil];
        if (self.onMoved) {
            self.onMoved(target);
        }
    }
}

- (CGPoint)snappedCenter {
    CGRect area = UIEdgeInsetsInsetRect(self.superview.bounds, self.superview.safeAreaInsets);
    CGFloat half = kBubbleSize / 2 + kEdgeMargin;
    CGFloat x = self.center.x < CGRectGetMidX(area) ? CGRectGetMinX(area) + half : CGRectGetMaxX(area) - half;
    CGFloat y = MIN(MAX(self.center.y, CGRectGetMinY(area) + half), CGRectGetMaxY(area) - half);
    return CGPointMake(x, y);
}

@end

#pragma mark - Marker

@implementation ATMarkerView {
    UIColor *_color;
}

- (instancetype)initWithNumber:(NSInteger)number color:(UIColor *)color diameter:(CGFloat)diameter {
    if ((self = [super initWithFrame:CGRectMake(0, 0, diameter, diameter)])) {
        _color = color;
        self.layer.cornerRadius = diameter / 2;
        self.layer.borderWidth = 2.5;
        self.layer.borderColor = color.CGColor;
        self.backgroundColor = [color colorWithAlphaComponent:0.28];
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.4;
        self.layer.shadowRadius = 4;
        self.layer.shadowOffset = CGSizeZero;

        if (number > 0) {
            UILabel *label = [[UILabel alloc] initWithFrame:self.bounds];
            label.text = [NSString stringWithFormat:@"%ld", (long)number];
            label.textAlignment = NSTextAlignmentCenter;
            label.textColor = [UIColor whiteColor];
            label.font = [UIFont systemFontOfSize:diameter * 0.36 weight:UIFontWeightHeavy];
            [self addSubview:label];
        } else {
            self.backgroundColor = [color colorWithAlphaComponent:0.55];
        }
        [self addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragged:)]];
    }
    return self;
}

- (void)dragged:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self.superview];
    CGRect bounds = self.superview.bounds;
    self.center = CGPointMake(MIN(MAX(self.center.x + translation.x, 0), CGRectGetMaxX(bounds)),
                              MIN(MAX(self.center.y + translation.y, 0), CGRectGetMaxY(bounds)));
    [pan setTranslation:CGPointZero inView:self.superview];
    BOOL finished = pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled;
    if (pan.state == UIGestureRecognizerStateBegan) {
        self.transform = CGAffineTransformMakeScale(1.2, 1.2);
    } else if (finished) {
        self.transform = CGAffineTransformIdentity;
    }
    if (self.onDrag) {
        self.onDrag(self, finished);
    }
}

- (void)setActive:(BOOL)active {
    _active = active;
    [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        self.transform = active ? CGAffineTransformMakeScale(1.25, 1.25) : CGAffineTransformIdentity;
        self.backgroundColor = [self->_color colorWithAlphaComponent:active ? 0.75 : 0.28];
    } completion:nil];
}

@end

#pragma mark - Gradient button

@interface ATGradientButton : UIButton
@property (nonatomic, readonly) CAGradientLayer *gradient;
@end

@implementation ATGradientButton
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _gradient = [CAGradientLayer layer];
        _gradient.startPoint = CGPointMake(0, 0);
        _gradient.endPoint = CGPointMake(1, 1);
        [self.layer insertSublayer:_gradient atIndex:0];
        self.layer.cornerRadius = 16;
        self.clipsToBounds = YES;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _gradient.frame = self.bounds;
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.75 : 1;
}
@end

#pragma mark - Panel

@implementation ATPanelView {
    ATSession *_session;
    UIStackView *_stack;
    UILabel *_stepsCount;
    UIScrollView *_stepsScroll;
    UIStackView *_stepsStack;
    NSLayoutConstraint *_stepsHeight;
    UILabel *_emptyLabel;
    NSMutableArray<UIView *> *_rows;
    NSInteger _highlighted;
    UISlider *_tapSlider, *_swipeDelaySlider, *_swipeTimeSlider;
    UILabel *_tapValue, *_swipeDelayValue, *_swipeTimeValue, *_loopValue;
    UIStepper *_loopStepper;
    UISwitch *_touchesSwitch;
    ATGradientButton *_runButton;
    UILabel *_statusLabel;
}

- (instancetype)initWithSession:(ATSession *)session {
    if ((self = [super initWithFrame:CGRectZero])) {
        _session = session;
        _rows = [NSMutableArray array];
        _highlighted = -1;
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.45;
        self.layer.shadowRadius = 24;
        self.layer.shadowOffset = CGSizeMake(0, 10);
        [self buildViews];
        [self reloadSteps];
        [self updateRunState];
    }
    return self;
}

- (void)buildViews {
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    blur.translatesAutoresizingMaskIntoConstraints = NO;
    blur.layer.cornerRadius = 26;
    blur.layer.cornerCurve = kCACornerCurveContinuous;
    blur.clipsToBounds = YES;
    blur.layer.borderWidth = 1;
    blur.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
    [self addSubview:blur];

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.showsVerticalScrollIndicator = NO;
    scroll.alwaysBounceVertical = NO;
    [blur.contentView addSubview:scroll];

    _stack = [[UIStackView alloc] init];
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.spacing = 14;
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:_stack];

    NSLayoutConstraint *fitContent = [self.heightAnchor constraintEqualToAnchor:_stack.heightAnchor constant:36];
    fitContent.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [blur.topAnchor constraintEqualToAnchor:self.topAnchor],
        [blur.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [blur.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [blur.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:blur.contentView.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:blur.contentView.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:blur.contentView.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:blur.contentView.trailingAnchor],
        [_stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:18],
        [_stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-18],
        [_stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:18],
        [_stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-18],
        fitContent,
    ]];

    [_stack addArrangedSubview:[self headerView]];
    [_stack addArrangedSubview:[self stepsSection]];
    [_stack addArrangedSubview:[self editButtons]];
    [_stack addArrangedSubview:[self timingSection]];
    [_stack addArrangedSubview:[self runSection]];
}

#pragma mark Sections

- (UIView *)headerView {
    UIView *iconBox = [[UIView alloc] init];
    iconBox.backgroundColor = ATTapColor();
    iconBox.layer.cornerRadius = 10;
    iconBox.layer.cornerCurve = kCACornerCurveContinuous;
    UIImageView *icon = [[UIImageView alloc] initWithImage:ATSymbol(@"hand.tap.fill", 17, UIFontWeightBold)];
    icon.tintColor = [UIColor whiteColor];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [iconBox addSubview:icon];
    iconBox.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [iconBox.widthAnchor constraintEqualToConstant:36],
        [iconBox.heightAnchor constraintEqualToConstant:36],
        [icon.centerXAnchor constraintEqualToAnchor:iconBox.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:iconBox.centerYAnchor],
    ]];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"AutoTap";
    title.font = [UIFont systemFontOfSize:21 weight:UIFontWeightBold];
    title.textColor = [UIColor labelColor];
    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.text = @"Powered by TouchSynth";
    subtitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    subtitle.textColor = [UIColor secondaryLabelColor];
    UIStackView *titles = [[UIStackView alloc] initWithArrangedSubviews:@[title, subtitle]];
    titles.axis = UILayoutConstraintAxisVertical;
    titles.spacing = 1;

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setImage:ATSymbol(@"xmark.circle.fill", 24, UIFontWeightSemibold) forState:UIControlStateNormal];
    close.tintColor = [UIColor tertiaryLabelColor];
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [close setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[iconBox, titles, [UIView new], close]];
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12;
    return row;
}

- (UILabel *)sectionLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.attributedText = [[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: [UIColor secondaryLabelColor],
        NSKernAttributeName: @1.2,
    }];
    return label;
}

- (UIView *)stepsSection {
    _stepsCount = [[UILabel alloc] init];
    _stepsCount.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    _stepsCount.textColor = [UIColor secondaryLabelColor];
    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[[self sectionLabel:@"STEPS"], [UIView new], _stepsCount]];

    UIView *box = [[UIView alloc] init];
    box.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    box.layer.cornerRadius = 16;
    box.layer.cornerCurve = kCACornerCurveContinuous;
    box.clipsToBounds = YES;
    box.translatesAutoresizingMaskIntoConstraints = NO;

    _stepsScroll = [[UIScrollView alloc] init];
    _stepsScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:_stepsScroll];

    _stepsStack = [[UIStackView alloc] init];
    _stepsStack.axis = UILayoutConstraintAxisVertical;
    _stepsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_stepsScroll addSubview:_stepsStack];

    _emptyLabel = [[UILabel alloc] init];
    _emptyLabel.text = @"No steps yet.\nTap Record, then tap or drag on screen.";
    _emptyLabel.numberOfLines = 0;
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.font = [UIFont systemFontOfSize:13];
    _emptyLabel.textColor = [UIColor tertiaryLabelColor];
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:_emptyLabel];

    _stepsHeight = [box.heightAnchor constraintEqualToConstant:70];
    [NSLayoutConstraint activateConstraints:@[
        _stepsHeight,
        [_stepsScroll.topAnchor constraintEqualToAnchor:box.topAnchor],
        [_stepsScroll.bottomAnchor constraintEqualToAnchor:box.bottomAnchor],
        [_stepsScroll.leadingAnchor constraintEqualToAnchor:box.leadingAnchor],
        [_stepsScroll.trailingAnchor constraintEqualToAnchor:box.trailingAnchor],
        [_stepsStack.topAnchor constraintEqualToAnchor:_stepsScroll.contentLayoutGuide.topAnchor],
        [_stepsStack.bottomAnchor constraintEqualToAnchor:_stepsScroll.contentLayoutGuide.bottomAnchor],
        [_stepsStack.leadingAnchor constraintEqualToAnchor:_stepsScroll.frameLayoutGuide.leadingAnchor],
        [_stepsStack.trailingAnchor constraintEqualToAnchor:_stepsScroll.frameLayoutGuide.trailingAnchor],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
        [_emptyLabel.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:12],
        [_emptyLabel.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-12],
    ]];

    UIStackView *section = [[UIStackView alloc] initWithArrangedSubviews:@[header, box]];
    section.axis = UILayoutConstraintAxisVertical;
    section.spacing = 8;
    return section;
}

- (UIButton *)pillWithTitle:(NSString *)title symbol:(NSString *)symbol tint:(UIColor *)tint action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:ATSymbol(symbol, 13, UIFontWeightBold) forState:UIControlStateNormal];
    [button setTitle:[@" " stringByAppendingString:title] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    button.tintColor = tint;
    [button setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    button.backgroundColor = [UIColor colorWithWhite:1 alpha:0.09];
    button.layer.cornerRadius = 12;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    [button.heightAnchor constraintEqualToConstant:40].active = YES;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIView *)editButtons {
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self pillWithTitle:@"Record" symbol:@"record.circle" tint:ATStopColor() action:@selector(recordTapped)],
        [self pillWithTitle:@"Undo" symbol:@"arrow.uturn.backward" tint:[UIColor labelColor] action:@selector(undoTapped)],
        [self pillWithTitle:@"Clear" symbol:@"trash" tint:[UIColor labelColor] action:@selector(clearTapped)],
    ]];
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = 8;
    return row;
}

- (UIView *)sliderRowWithTitle:(NSString *)title
                        slider:(UISlider *__strong *)outSlider
                         value:(UILabel *__strong *)outValue
                          tint:(UIColor *)tint {
    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    label.textColor = [UIColor labelColor];
    UILabel *value = [[UILabel alloc] init];
    value.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
    value.textColor = tint;
    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[label, [UIView new], value]];

    UISlider *slider = [[UISlider alloc] init];
    slider.minimumTrackTintColor = tint;
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[top, slider]];
    row.axis = UILayoutConstraintAxisVertical;
    row.spacing = 4;
    *outSlider = slider;
    *outValue = value;
    return row;
}

- (UIView *)timingSection {
    UIView *tapRow = [self sliderRowWithTitle:@"Delay after tap" slider:&_tapSlider value:&_tapValue tint:ATTapColor()];
    UIView *swipeDelayRow = [self sliderRowWithTitle:@"Delay after swipe" slider:&_swipeDelaySlider value:&_swipeDelayValue tint:ATSwipeColor()];
    UIView *swipeTimeRow = [self sliderRowWithTitle:@"Swipe time" slider:&_swipeTimeSlider value:&_swipeTimeValue tint:ATSwipeColor()];
    _tapSlider.value = ATSliderValue(_session.tapDelay, kMinDelay, kMaxDelay);
    _swipeDelaySlider.value = ATSliderValue(_session.swipeDelay, kMinDelay, kMaxDelay);
    _swipeTimeSlider.value = ATSliderValue(_session.swipeDuration, kMinSwipeTime, kMaxSwipeTime);

    UILabel *loopLabel = [[UILabel alloc] init];
    loopLabel.text = @"Repeat";
    loopLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    _loopValue = [[UILabel alloc] init];
    _loopValue.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
    _loopValue.textColor = ATGoColor();
    _loopStepper = [[UIStepper alloc] init];
    _loopStepper.minimumValue = 0;
    _loopStepper.maximumValue = sizeof(kLoopValues) / sizeof(kLoopValues[0]) - 1;
    for (NSUInteger i = 0; i < sizeof(kLoopValues) / sizeof(kLoopValues[0]); i++) {
        if (kLoopValues[i] == _session.loopCount) {
            _loopStepper.value = i;
        }
    }
    [_loopStepper addTarget:self action:@selector(loopChanged) forControlEvents:UIControlEventValueChanged];
    UIStackView *loopRow = [[UIStackView alloc] initWithArrangedSubviews:@[loopLabel, [UIView new], _loopValue, _loopStepper]];
    loopRow.alignment = UIStackViewAlignmentCenter;
    loopRow.spacing = 12;

    UILabel *touchesLabel = [[UILabel alloc] init];
    touchesLabel.text = @"Show touches";
    touchesLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    _touchesSwitch = [[UISwitch alloc] init];
    _touchesSwitch.onTintColor = ATGoColor();
    _touchesSwitch.on = _session.showTouches;
    [_touchesSwitch addTarget:self action:@selector(touchesChanged) forControlEvents:UIControlEventValueChanged];
    UIStackView *touchesRow = [[UIStackView alloc] initWithArrangedSubviews:@[touchesLabel, [UIView new], _touchesSwitch]];
    touchesRow.alignment = UIStackViewAlignmentCenter;

    [self refreshTimingLabels];
    UIStackView *section = [[UIStackView alloc] initWithArrangedSubviews:@[[self sectionLabel:@"TIMING"], tapRow, swipeDelayRow, swipeTimeRow, loopRow, touchesRow]];
    section.axis = UILayoutConstraintAxisVertical;
    section.spacing = 12;
    [section setCustomSpacing:6 afterView:section.arrangedSubviews.firstObject];
    return section;
}

- (UIView *)runSection {
    _runButton = [ATGradientButton buttonWithType:UIButtonTypeCustom];
    _runButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    _runButton.tintColor = [UIColor whiteColor];
    [_runButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_runButton.heightAnchor constraintEqualToConstant:54].active = YES;
    [_runButton addTarget:self action:@selector(runTapped) forControlEvents:UIControlEventTouchUpInside];

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    _statusLabel.textColor = [UIColor secondaryLabelColor];
    _statusLabel.textAlignment = NSTextAlignmentCenter;

    UIStackView *section = [[UIStackView alloc] initWithArrangedSubviews:@[_runButton, _statusLabel]];
    section.axis = UILayoutConstraintAxisVertical;
    section.spacing = 8;
    return section;
}

#pragma mark Steps

- (UIView *)rowForAction:(ATAction *)action index:(NSInteger)index {
    BOOL swipe = action.type == ATActionTypeSwipe;
    UIColor *color = swipe ? ATSwipeColor() : ATTapColor();

    UILabel *badge = [[UILabel alloc] init];
    badge.text = [NSString stringWithFormat:@"%ld", (long)index + 1];
    badge.textAlignment = NSTextAlignmentCenter;
    badge.font = [UIFont systemFontOfSize:13 weight:UIFontWeightHeavy];
    badge.textColor = [UIColor whiteColor];
    badge.backgroundColor = color;
    badge.layer.cornerRadius = 14;
    badge.clipsToBounds = YES;
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    [badge.widthAnchor constraintEqualToConstant:28].active = YES;
    [badge.heightAnchor constraintEqualToConstant:28].active = YES;

    UILabel *title = [[UILabel alloc] init];
    title.text = swipe ? @"Swipe" : @"Tap";
    title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    UILabel *detail = [[UILabel alloc] init];
    detail.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    detail.textColor = [UIColor secondaryLabelColor];
    detail.text = swipe
        ? [NSString stringWithFormat:@"%.0f, %.0f  →  %.0f, %.0f", action.start.x, action.start.y, action.end.x, action.end.y]
        : [NSString stringWithFormat:@"x %.0f   y %.0f", action.start.x, action.start.y];
    UIStackView *texts = [[UIStackView alloc] initWithArrangedSubviews:@[title, detail]];
    texts.axis = UILayoutConstraintAxisVertical;

    UIButton *remove = [UIButton buttonWithType:UIButtonTypeSystem];
    [remove setImage:ATSymbol(@"minus.circle.fill", 20, UIFontWeightSemibold) forState:UIControlStateNormal];
    remove.tintColor = [UIColor tertiaryLabelColor];
    remove.tag = index;
    [remove addTarget:self action:@selector(removeTapped:) forControlEvents:UIControlEventTouchUpInside];
    [remove setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[badge, texts, remove]];
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12;
    row.layoutMargins = UIEdgeInsetsMake(0, 12, 0, 12);
    row.layoutMarginsRelativeArrangement = YES;
    [row.heightAnchor constraintEqualToConstant:kStepRowHeight].active = YES;
    return row;
}

- (void)reloadSteps {
    for (UIView *row in _rows) {
        [row removeFromSuperview];
    }
    [_rows removeAllObjects];
    NSArray<ATAction *> *actions = _session.actions;
    NSInteger taps = 0;
    for (NSInteger i = 0; i < (NSInteger)actions.count; i++) {
        UIView *row = [self rowForAction:actions[i] index:i];
        [_stepsStack addArrangedSubview:row];
        [_rows addObject:row];
        taps += actions[i].type == ATActionTypeTap;
    }
    NSInteger swipes = (NSInteger)actions.count - taps;
    _stepsCount.text = actions.count ? [NSString stringWithFormat:@"%ld tap%@ · %ld swipe%@",
                                        (long)taps, taps == 1 ? @"" : @"s", (long)swipes, swipes == 1 ? @"" : @"s"] : @"";
    _emptyLabel.hidden = actions.count > 0;
    _stepsHeight.constant = actions.count ? MIN(actions.count, kVisibleStepRows) * kStepRowHeight : 70;
    _highlighted = -1;
    [self updateRunState];
}

- (void)highlightStep:(NSInteger)index {
    if (_highlighted >= 0 && _highlighted < (NSInteger)_rows.count) {
        _rows[_highlighted].backgroundColor = [UIColor clearColor];
    }
    _highlighted = index;
    if (index >= 0 && index < (NSInteger)_rows.count) {
        UIView *row = _rows[index];
        BOOL swipe = _session.actions[index].type == ATActionTypeSwipe;
        row.backgroundColor = [(swipe ? ATSwipeColor() : ATTapColor()) colorWithAlphaComponent:0.2];
        [_stepsScroll scrollRectToVisible:row.frame animated:YES];
    }
    [self updateStatus];
}

- (void)updateRunState {
    BOOL running = _session.running;
    [_runButton setImage:ATSymbol(running ? @"stop.fill" : @"play.fill", 16, UIFontWeightBold) forState:UIControlStateNormal];
    [_runButton setTitle:running ? @"  Stop" : @"  Start" forState:UIControlStateNormal];
    UIColor *base = running ? ATStopColor() : ATGoColor();
    CGFloat h, s, b, a;
    [base getHue:&h saturation:&s brightness:&b alpha:&a];
    _runButton.gradient.colors = @[(id)base.CGColor, (id)[UIColor colorWithHue:h saturation:s brightness:b * 0.72 alpha:a].CGColor];
    if (!running) {
        [self highlightStep:-1];
    }
    [self updateStatus];
}

- (void)updateStatus {
    NSUInteger count = _session.actions.count;
    if (_session.running) {
        NSString *loops = _session.loopCount ? [NSString stringWithFormat:@"%ld of %ld", (long)_session.currentLoop, (long)_session.loopCount]
                                             : [NSString stringWithFormat:@"%ld", (long)_session.currentLoop];
        _statusLabel.text = [NSString stringWithFormat:@"Loop %@  ·  Step %ld of %lu", loops, (long)_session.currentIndex + 1, (unsigned long)count];
    } else {
        _statusLabel.text = count ? @"Tap the floating button to stop a run" : @"Record at least one step to start";
    }
}

- (void)showMessage:(NSString *)message {
    _statusLabel.text = message;
    _statusLabel.textColor = ATStopColor();
    CAKeyframeAnimation *shake = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    shake.values = @[@0, @-10, @10, @-6, @6, @0];
    shake.duration = 0.35;
    [self.layer addAnimation:shake forKey:@"shake"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self->_statusLabel.textColor = [UIColor secondaryLabelColor];
        [self updateStatus];
    });
}

#pragma mark Controls

- (void)refreshTimingLabels {
    _tapValue.text = ATFormatSeconds(_session.tapDelay);
    _swipeDelayValue.text = ATFormatSeconds(_session.swipeDelay);
    _swipeTimeValue.text = ATFormatSeconds(_session.swipeDuration);
    _loopValue.text = ATFormatLoops(_session.loopCount);
}

- (void)sliderChanged:(UISlider *)slider {
    if (slider == _tapSlider) {
        _session.tapDelay = ATSeconds(slider.value, kMinDelay, kMaxDelay);
    } else if (slider == _swipeDelaySlider) {
        _session.swipeDelay = ATSeconds(slider.value, kMinDelay, kMaxDelay);
    } else {
        _session.swipeDuration = ATSeconds(slider.value, kMinSwipeTime, kMaxSwipeTime);
    }
    [self refreshTimingLabels];
}

- (void)loopChanged {
    _session.loopCount = kLoopValues[(NSInteger)_loopStepper.value];
    [self refreshTimingLabels];
    [self updateStatus];
}

- (void)touchesChanged {
    _session.showTouches = _touchesSwitch.on;
}

- (void)recordTapped {
    if (self.onRecord) {
        self.onRecord();
    }
}

- (void)undoTapped {
    [_session removeLastAction];
}

- (void)clearTapped {
    [_session removeAllActions];
}

- (void)removeTapped:(UIButton *)button {
    [_session removeActionAtIndex:button.tag];
}

- (void)closeTapped {
    if (self.onClose) {
        self.onClose();
    }
}

- (void)runTapped {
    if (self.onToggleRun) {
        self.onToggleRun();
    }
}

@end
