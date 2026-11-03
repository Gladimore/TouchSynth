#import "TSPrivateUIKit.h"

#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>

#if !__has_feature(objc_arc)
#error TouchSynth must be compiled with -fobjc-arc
#endif

// Layout of the GSEvent UIKit reads in _initWithEvent:touches:. Offsets match the
// GSEventProxy metadata in iGameGod (flags at 0x08, x1 at 0x14, sizeX at 0x68...).
@interface TSGSEventProxy : NSObject {
@public
    unsigned int flags;
    unsigned int type;
    unsigned int ignored1;
    float x1;
    float y1;
    float x2;
    float y2;
    unsigned int ignored2[10];
    unsigned int ignored3[7];
    float sizeX;
    float sizeY;
    float x3;
    float y3;
    unsigned int ignored4[3];
}
@end

@implementation TSGSEventProxy
@end

static const unsigned int kGSEventTypeHand = 3001; // 0xbb9
static const unsigned int kGSFlagsTouchActive = 0x3010180;
static const unsigned int kGSFlagsTouchFinished = 0x1010180;

static const unsigned short kTouchFlagFirstTouchForView = 1 << 0;
static const unsigned short kTouchFlagIsTap = 1 << 1;
static const double kTapFlagClearDistance = 2.0;

static char kFallbackWindowKey;
static char kFallbackViewKey;

#pragma mark - Ivars

static void *TSIvarPointer(id object, const char *name) {
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    return ivar ? (char *)(__bridge void *)object + ivar_getOffset(ivar) : NULL;
}

// iGameGod always writes 64 bits here. Sizing from the encoding avoids spilling
// into the next ivar if UIKit declares the field narrower.
static BOOL TSWriteInteger(id object, const char *name, long long value) {
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    if (!type) {
        return NO;
    }
    void *pointer = (char *)(__bridge void *)object + ivar_getOffset(ivar);
    switch (type[0]) {
        case 'q': case 'Q': case 'l': case 'L':
            *(long long *)pointer = value;
            return YES;
        case 'i': case 'I':
            *(int *)pointer = (int)value;
            return YES;
        case 's': case 'S':
            *(short *)pointer = (short)value;
            return YES;
        default:
            return NO;
    }
}

static long long TSReadInteger(id object, const char *name) {
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    if (!type) {
        return 0;
    }
    void *pointer = (char *)(__bridge void *)object + ivar_getOffset(ivar);
    switch (type[0]) {
        case 'q': case 'Q': case 'l': case 'L':
            return *(long long *)pointer;
        case 'i': case 'I':
            return *(int *)pointer;
        case 's': case 'S':
            return *(short *)pointer;
        default:
            return 0;
    }
}

static NSTimeInterval TSTimestamp(void) {
    return [NSProcessInfo processInfo].systemUptime;
}

#pragma mark - Hooks

static id (*gOriginalTouchView)(id, SEL);
static id (*gOriginalTouchWindow)(id, SEL);
static BOOL (*gOriginalSendAction)(id, SEL, SEL, id, id, id);

static __weak UIControl *gTrackedControl;
static long gTrackedActionCount;

// The stored ivars do not always read back on a synthetic touch, and every later
// phase needs them, so fall back to the objects recorded at creation.
static id TSHookedTouchView(id self, SEL _cmd) {
    return gOriginalTouchView(self, _cmd) ?: objc_getAssociatedObject(self, &kFallbackViewKey);
}

static id TSHookedTouchWindow(id self, SEL _cmd) {
    return gOriginalTouchWindow(self, _cmd) ?: objc_getAssociatedObject(self, &kFallbackWindowKey);
}

static BOOL TSHookedSendAction(id self, SEL _cmd, SEL action, id target, id sender, id event) {
    BOOL result = gOriginalSendAction(self, _cmd, action, target, sender, event);
    UIControl *tracked = gTrackedControl;
    if (tracked && sender == tracked) {
        gTrackedActionCount++;
    }
    return result;
}

void TSInstallHooks(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method method = class_getInstanceMethod([UITouch class], @selector(view));
        if (method) {
            gOriginalTouchView = (void *)method_setImplementation(method, (IMP)TSHookedTouchView);
        }
        method = class_getInstanceMethod([UITouch class], @selector(window));
        if (method) {
            gOriginalTouchWindow = (void *)method_setImplementation(method, (IMP)TSHookedTouchWindow);
        }
        method = class_getInstanceMethod([UIApplication class], @selector(sendAction:to:from:forEvent:));
        if (method) {
            gOriginalSendAction = (void *)method_setImplementation(method, (IMP)TSHookedSendAction);
        }
    });
}

void TSTrackControl(UIControl *control) {
    gTrackedControl = control;
    gTrackedActionCount = 0;
}

UIControl *TSTrackedControl(void) {
    return gTrackedControl;
}

long TSTrackedActionCount(void) {
    return gTrackedActionCount;
}

#pragma mark - Touch

static void TSSendSetterIfAvailable(id object, NSString *selectorName, id value) {
    SEL selector = NSSelectorFromString(selectorName);
    if ([object respondsToSelector:selector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(object, selector, value);
    }
}

// Setters first: they retain to match what UITouch's dealloc releases, whereas
// object_setIvar on a non-ARC ivar assigns without retaining. iGameGod tries the
// raw ivar first. The ivar and KVC remain for OS versions without the setters.
// Success is read from the ivar because the hooked getters return the fallback.
static void TSSetTouchObject(UITouch *touch, id value, NSString *name, const char *ivarName) {
    Ivar ivar = class_getInstanceVariable(object_getClass(touch), ivarName);
    if (ivar && object_getIvar(touch, ivar) == value) {
        return;
    }
    NSString *capitalized = name.capitalizedString;
    TSSendSetterIfAvailable(touch, [NSString stringWithFormat:@"set%@:", capitalized], value);
    if (ivar && object_getIvar(touch, ivar) == value) {
        return;
    }
    TSSendSetterIfAvailable(touch, [NSString stringWithFormat:@"_set%@:", capitalized], value);
    if (ivar && object_getIvar(touch, ivar) == value) {
        return;
    }
    if (ivar) {
        object_setIvar(touch, ivar, value);
        if (object_getIvar(touch, ivar) == value) {
            return;
        }
    }
    @try {
        [touch setValue:value forKey:name];
    } @catch (__unused NSException *exception) {
    }
}

void TSTouchSetWindowAndView(UITouch *touch, UIWindow *window, UIView *view) {
    if (window) {
        objc_setAssociatedObject(touch, &kFallbackWindowKey, window, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        TSSetTouchObject(touch, window, @"window", "_window");
    }
    if (view) {
        objc_setAssociatedObject(touch, &kFallbackViewKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        TSSetTouchObject(touch, view, @"view", "_view");
    }
}

UITouch *TSCreateTouch(UIWindow *window, UIView *view, CGPoint windowPoint) {
    UITouch *touch = [[UITouch alloc] init];
    if (!touch) {
        return nil;
    }
    CGPoint *location = TSIvarPointer(touch, "_locationInWindow");
    CGPoint *previous = TSIvarPointer(touch, "_previousLocationInWindow");
    unsigned short *flags = TSIvarPointer(touch, "_touchFlags");
    NSTimeInterval *timestamp = TSIvarPointer(touch, "_timestamp");
    if (!location || !previous || !flags || !timestamp) {
        return nil;
    }
    if (!TSWriteInteger(touch, "_tapCount", 1) || !TSWriteInteger(touch, "_phase", UITouchPhaseBegan)) {
        return nil;
    }
    *location = windowPoint;
    *previous = windowPoint;
    *flags |= kTouchFlagFirstTouchForView | kTouchFlagIsTap;
    *timestamp = TSTimestamp();
    TSTouchSetWindowAndView(touch, window, view);
    return touch;
}

void TSTouchSetPhase(UITouch *touch, UITouchPhase phase) {
    NSTimeInterval *timestamp = TSIvarPointer(touch, "_timestamp");
    if (timestamp && TSWriteInteger(touch, "_phase", phase)) {
        *timestamp = TSTimestamp();
    }
}

void TSTouchSetLocation(UITouch *touch, CGPoint windowPoint) {
    CGPoint *location = TSIvarPointer(touch, "_locationInWindow");
    CGPoint *previous = TSIvarPointer(touch, "_previousLocationInWindow");
    NSTimeInterval *timestamp = TSIvarPointer(touch, "_timestamp");
    if (!location || !previous || !timestamp) {
        return;
    }
    *previous = *location;
    *location = windowPoint;
    if (fabs(windowPoint.x - previous->x) > kTapFlagClearDistance ||
        fabs(windowPoint.y - previous->y) > kTapFlagClearDistance) {
        TSTouchSetTapFlag(touch, NO);
    }
    *timestamp = TSTimestamp();
}

void TSTouchSetIdentifier(UITouch *touch, NSInteger identifier) {
    TSWriteInteger(touch, "_touchIdentifier", identifier);
}

NSInteger TSTouchGetIdentifier(UITouch *touch) {
    return (NSInteger)TSReadInteger(touch, "_touchIdentifier");
}

void TSTouchSetTapFlag(UITouch *touch, BOOL isTap) {
    unsigned short *flags = TSIvarPointer(touch, "_touchFlags");
    if (flags) {
        *flags = (unsigned short)((*flags & ~kTouchFlagIsTap) | (isTap ? kTouchFlagIsTap : 0));
    }
}

BOOL TSTouchGetTapFlag(UITouch *touch) {
    unsigned short *flags = TSIvarPointer(touch, "_touchFlags");
    return flags ? (*flags & kTouchFlagIsTap) != 0 : NO;
}

#pragma mark - Event

typedef id (*TSEventInitializer)(__attribute__((ns_consumed)) id, SEL, id, id) __attribute__((ns_returns_retained));

UIEvent *TSCreateEvent(UITouch *touch) {
    Class eventClass = objc_getClass("UITouchesEvent") ?: [UIEvent class];
    SEL initializer = NSSelectorFromString(@"_initWithEvent:touches:");
    if (!class_respondsToSelector(eventClass, initializer)) {
        return nil;
    }

    CGPoint location = [touch locationInView:touch.window];
    CGPoint previous = [touch previousLocationInView:touch.window];
    TSGSEventProxy *proxy = [[TSGSEventProxy alloc] init];
    proxy->x1 = (float)location.x;
    proxy->y1 = (float)location.y;
    proxy->x2 = (float)previous.x;
    proxy->y2 = (float)previous.y;
    proxy->x3 = (float)location.x;
    proxy->y3 = (float)location.y;
    proxy->sizeX = 1.0f;
    proxy->sizeY = 1.0f;
    BOOL finished = touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled;
    proxy->flags = finished ? kGSFlagsTouchFinished : kGSFlagsTouchActive;
    proxy->type = kGSEventTypeHand;

    UIEvent *event = nil;
    @try {
        event = ((TSEventInitializer)objc_msgSend)([eventClass alloc], initializer, proxy, [NSSet setWithObject:touch]);
    } @catch (__unused NSException *exception) {
        return nil;
    }
    NSTimeInterval *timestamp = event ? TSIvarPointer(event, "_timestamp") : NULL;
    if (timestamp) {
        *timestamp = TSTimestamp();
    }
    return event;
}

#pragma mark - Diagnostics

NSDictionary<NSString *, NSNumber *> *TSPrivateRuntimeDiagnostics(void) {
    NSMutableDictionary<NSString *, NSNumber *> *result = [NSMutableDictionary dictionary];
    const char *const touchIvars[] = {
        "_tapCount", "_locationInWindow", "_previousLocationInWindow", "_phase",
        "_touchFlags", "_timestamp", "_touchIdentifier", "_window", "_view",
    };
    for (size_t i = 0; i < sizeof(touchIvars) / sizeof(touchIvars[0]); i++) {
        BOOL present = class_getInstanceVariable([UITouch class], touchIvars[i]) != NULL;
        result[[NSString stringWithFormat:@"touch.%s", touchIvars[i]]] = @(present);
    }
    Class eventClass = objc_getClass("UITouchesEvent");
    result[@"event.UITouchesEvent"] = @((BOOL)(eventClass != Nil));
    result[@"event._initWithEvent:touches:"] =
        @(class_respondsToSelector(eventClass ?: [UIEvent class], NSSelectorFromString(@"_initWithEvent:touches:")));
    result[@"touch.setWindow:"] = @([UITouch instancesRespondToSelector:NSSelectorFromString(@"setWindow:")]);
    result[@"touch.setView:"] = @([UITouch instancesRespondToSelector:NSSelectorFromString(@"setView:")]);
    return result;
}
