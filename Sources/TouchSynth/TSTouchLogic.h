// Pure decision logic, free of UIKit so it can be unit tested on any host.
#ifndef TS_TOUCH_LOGIC_H
#define TS_TOUCH_LOGIC_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// What to do after an ended touch failed to produce a native response.
typedef enum {
    TSFallbackNone = 0,
    TSFallbackControlActions = 1,
    TSFallbackTapGestures = 2,
    TSFallbackDirectTap = 3,
    TSFallbackCellSelection = 4,
} TSFallback;

typedef struct {
    bool hasControl;
    bool controlHasTargets;
    bool hasTapGestures;
    bool hasCellAncestor;
    bool isKeyWindow;
    bool touchIsTap;
    bool pointInsideTarget;
    long nativeActionCount; // actions UIKit already sent for the control
} TSFallbackInputs;

// Port of FUN_0057efe4.
TSFallback TSFallbackForInputs(TSFallbackInputs inputs);

// Port of FUN_0058ed7c: clamps to the scrollable range, inset-adjusted.
void TSClampContentOffset(double *x, double *y,
                          double insetTop, double insetLeft,
                          double insetBottom, double insetRight,
                          double contentWidth, double contentHeight,
                          double boundsWidth, double boundsHeight);

// A touch stops counting as a tap beyond this distance (12pt, compared squared).
bool TSExceedsTapSlop(double dx, double dy);

#ifdef __cplusplus
}
#endif
#endif
