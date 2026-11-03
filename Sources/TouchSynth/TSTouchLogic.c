#include "TSTouchLogic.h"

TSFallback TSFallbackForInputs(TSFallbackInputs in) {
    if (in.nativeActionCount != 0 || !in.pointInsideTarget) {
        return TSFallbackNone;
    }
    if (in.hasControl && in.controlHasTargets) {
        return TSFallbackControlActions;
    }
    if (!in.touchIsTap) {
        return TSFallbackNone;
    }
    TSFallback tapFallback = in.hasTapGestures ? TSFallbackTapGestures : TSFallbackDirectTap;
    if (in.hasControl || !in.hasCellAncestor) {
        return tapFallback;
    }
    return in.isKeyWindow ? TSFallbackNone : TSFallbackCellSelection;
}

static double TSClamp(double value, double min, double max) {
    if (max < min) {
        max = min;
    }
    if (value < min) {
        return min;
    }
    return value > max ? max : value;
}

void TSClampContentOffset(double *x, double *y,
                          double insetTop, double insetLeft,
                          double insetBottom, double insetRight,
                          double contentWidth, double contentHeight,
                          double boundsWidth, double boundsHeight) {
    *x = TSClamp(*x, -insetLeft, contentWidth - boundsWidth + insetRight);
    *y = TSClamp(*y, -insetTop, contentHeight - boundsHeight + insetBottom);
}

bool TSExceedsTapSlop(double dx, double dy) {
    return dx * dx + dy * dy > 144.0;
}
