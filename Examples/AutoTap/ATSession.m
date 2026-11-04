#import "ATSession.h"

#import "TouchSynth.h"

static NSString *const kDefaultsKey = @"com.gladimore.autotap.v1";
static const NSTimeInterval kTapHoldTime = 0.05;

@interface ATAction ()
- (NSDictionary *)dictionary;
+ (nullable instancetype)actionWithDictionary:(NSDictionary *)dictionary;
@end

@implementation ATAction

+ (instancetype)tapAt:(CGPoint)point {
    ATAction *action = [[self alloc] init];
    action.type = ATActionTypeTap;
    action.start = point;
    action.end = point;
    return action;
}

+ (instancetype)swipeFrom:(CGPoint)start to:(CGPoint)end {
    ATAction *action = [[self alloc] init];
    action.type = ATActionTypeSwipe;
    action.start = start;
    action.end = end;
    return action;
}

- (NSDictionary *)dictionary {
    return @{
        @"type": @(self.type),
        @"x1": @(self.start.x), @"y1": @(self.start.y),
        @"x2": @(self.end.x), @"y2": @(self.end.y),
    };
}

+ (nullable instancetype)actionWithDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    ATAction *action = [[self alloc] init];
    action.type = [dictionary[@"type"] integerValue] == ATActionTypeSwipe ? ATActionTypeSwipe : ATActionTypeTap;
    action.start = CGPointMake([dictionary[@"x1"] doubleValue], [dictionary[@"y1"] doubleValue]);
    action.end = CGPointMake([dictionary[@"x2"] doubleValue], [dictionary[@"y2"] doubleValue]);
    return action;
}

@end

@implementation ATSession {
    NSMutableArray<ATAction *> *_actions;
    NSUInteger _generation; // bumped on stop so pending steps see they are stale
    BOOL _idleTimerWasDisabled;
}

+ (ATSession *)shared {
    static ATSession *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[ATSession alloc] init];
    });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _actions = [NSMutableArray array];
        _tapDelay = 0.5;
        _swipeDelay = 0.8;
        _swipeDuration = 0.25;
        _loopCount = 0;
        _showTouches = YES;
        [self loadSaved];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillResignActive)
                                                     name:UIApplicationWillResignActiveNotification
                                                   object:nil];
    }
    return self;
}

- (NSArray<ATAction *> *)actions {
    return [_actions copy];
}

#pragma mark Persistence

- (void)loadSaved {
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kDefaultsKey];
    if (!saved) {
        return;
    }
    for (NSDictionary *item in saved[@"actions"]) {
        ATAction *action = [ATAction actionWithDictionary:item];
        if (action) {
            [_actions addObject:action];
        }
    }
    if (saved[@"tapDelay"]) _tapDelay = [saved[@"tapDelay"] doubleValue];
    if (saved[@"swipeDelay"]) _swipeDelay = [saved[@"swipeDelay"] doubleValue];
    if (saved[@"swipeDuration"]) _swipeDuration = [saved[@"swipeDuration"] doubleValue];
    if (saved[@"loopCount"]) _loopCount = [saved[@"loopCount"] integerValue];
    if (saved[@"showTouches"]) _showTouches = [saved[@"showTouches"] boolValue];
    if (saved[@"bubbleX"]) _bubbleCenter = CGPointMake([saved[@"bubbleX"] doubleValue], [saved[@"bubbleY"] doubleValue]);
}

- (void)save {
    NSMutableArray *actions = [NSMutableArray array];
    for (ATAction *action in _actions) {
        [actions addObject:[action dictionary]];
    }
    [[NSUserDefaults standardUserDefaults] setObject:@{
        @"actions": actions,
        @"tapDelay": @(_tapDelay),
        @"swipeDelay": @(_swipeDelay),
        @"swipeDuration": @(_swipeDuration),
        @"loopCount": @(_loopCount),
        @"showTouches": @(_showTouches),
        @"bubbleX": @(_bubbleCenter.x),
        @"bubbleY": @(_bubbleCenter.y),
    } forKey:kDefaultsKey];
}

- (void)changed {
    [self save];
    if (self.onChange) {
        self.onChange();
    }
}

#pragma mark Editing

- (void)setTapDelay:(NSTimeInterval)tapDelay { _tapDelay = tapDelay; [self save]; }
- (void)setSwipeDelay:(NSTimeInterval)swipeDelay { _swipeDelay = swipeDelay; [self save]; }
- (void)setSwipeDuration:(NSTimeInterval)swipeDuration { _swipeDuration = swipeDuration; [self save]; }
- (void)setLoopCount:(NSInteger)loopCount { _loopCount = loopCount; [self save]; }
- (void)setShowTouches:(BOOL)showTouches { _showTouches = showTouches; [self save]; }
- (void)setBubbleCenter:(CGPoint)bubbleCenter { _bubbleCenter = bubbleCenter; [self save]; }

- (void)addAction:(ATAction *)action {
    [self stop];
    [_actions addObject:action];
    [self changed];
}

- (void)removeActionAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_actions.count) {
        return;
    }
    [self stop];
    [_actions removeObjectAtIndex:index];
    [self changed];
}

- (void)removeLastAction {
    [self removeActionAtIndex:(NSInteger)_actions.count - 1];
}

- (void)removeAllActions {
    [self stop];
    [_actions removeAllObjects];
    [self changed];
}

- (void)actionsDidChange {
    [self changed];
}

#pragma mark Running

- (void)start {
    if (_running || _actions.count == 0) {
        return;
    }
    _running = YES;
    _currentIndex = 0;
    _currentLoop = 1;
    _idleTimerWasDisabled = [UIApplication sharedApplication].idleTimerDisabled;
    [UIApplication sharedApplication].idleTimerDisabled = YES; // long runs shouldn't lock the screen
    if (self.onRunStateChange) {
        self.onRunStateChange();
    }
    [self playStepForGeneration:_generation];
}

- (void)stop {
    if (!_running) {
        return;
    }
    _running = NO;
    _generation++;
    [TSTouchSynthesizer.sharedSynthesizer cancelAllTouches];
    [UIApplication sharedApplication].idleTimerDisabled = _idleTimerWasDisabled;
    if (self.onRunStateChange) {
        self.onRunStateChange();
    }
}

- (void)applicationWillResignActive {
    [self stop];
}

- (void)playStepForGeneration:(NSUInteger)generation {
    if (generation != _generation || !_running) {
        return;
    }
    if (_currentIndex >= (NSInteger)_actions.count) {
        _currentIndex = 0;
        _currentLoop++;
        if (_loopCount > 0 && _currentLoop > _loopCount) {
            [self stop];
            return;
        }
    }
    NSInteger index = _currentIndex;
    ATAction *action = _actions[index];
    if (self.onStepStart) {
        self.onStepStart(index, action);
    }

    __weak ATSession *weakSelf = self;
    void (^finish)(BOOL) = ^(BOOL reachedTarget) {
        ATSession *strongSelf = weakSelf;
        if (!strongSelf || generation != strongSelf->_generation) {
            return;
        }
        if (strongSelf.onStepFinish) {
            strongSelf.onStepFinish(index, action, reachedTarget);
        }
        NSTimeInterval delay = action.type == ATActionTypeSwipe ? strongSelf.swipeDelay : strongSelf.tapDelay;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            ATSession *innerSelf = weakSelf;
            if (innerSelf && generation == innerSelf->_generation) {
                innerSelf->_currentIndex = index + 1;
                [innerSelf playStepForGeneration:generation];
            }
        });
    };

    TSTouchSynthesizer *synth = TSTouchSynthesizer.sharedSynthesizer;
    if (action.type == ATActionTypeSwipe) {
        [synth swipeFromPoint:action.start toPoint:action.end duration:self.swipeDuration completion:finish];
    } else {
        [synth tapAtPoint:action.start duration:kTapHoldTime completion:finish];
    }
}

@end
