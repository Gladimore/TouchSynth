// Host-side test: compares the readable port against the decompiled originals.
// Build: clang -I../Sources/TouchSynth logic_test.c ../Sources/TouchSynth/TSTouchLogic.c -o logic_test
#include <math.h>
#include <stdio.h>

#include "TSTouchLogic.h"

// Verbatim logic of FUN_0057efe4 (iGameGod.c:1155677). The caller packs its
// booleans into one word: control=bit0, targets=bit8, tapGestures=bit16,
// tapFlag=bit24, inside=bit32, cell=bit40, keyWindow=bit48.
static unsigned int fun_0057efe4(long param_1, unsigned long long param_2) {
    unsigned int uVar1, uVar2, uVar3;
    uVar1 = (unsigned int)(param_2 >> 8) & 1 & (unsigned int)param_2;
    uVar2 = 2;
    if ((param_2 & 0x10000) == 0) uVar2 = 3;
    if ((param_2 & 0x10000000000ULL) != 0) uVar2 = ((unsigned int)(param_2 >> 0x2e) ^ 0xffffffff) & 4;
    uVar3 = 2;
    if ((param_2 & 0x10000) == 0) uVar3 = 3;
    if ((param_2 & 1) != 0) uVar2 = uVar3;
    uVar3 = uVar1;
    if ((param_2 & 0x1000000) != 0) uVar3 = uVar2;
    if (uVar1 == 0) uVar1 = uVar3;
    uVar2 = 0;
    if ((param_2 & 0x100000000ULL) != 0) uVar2 = uVar1;
    uVar1 = 0;
    if (param_1 == 0) uVar1 = uVar2;
    return uVar1;
}

static int testFallbackTruthTable(void) {
    int failures = 0, cases = 0;
    for (unsigned bits = 0; bits < 256; bits++) {
        TSFallbackInputs in = {
            .hasControl = bits & 1,
            .controlHasTargets = bits & 2,
            .hasTapGestures = bits & 4,
            .touchIsTap = bits & 8,
            .pointInsideTarget = bits & 16,
            .hasCellAncestor = bits & 32,
            .isKeyWindow = bits & 64,
            .nativeActionCount = (bits & 128) ? 1 : 0,
        };
        unsigned long long packed =
            (unsigned long long)in.hasControl |
            ((unsigned long long)in.controlHasTargets << 8) |
            ((unsigned long long)in.hasTapGestures << 16) |
            ((unsigned long long)in.touchIsTap << 24) |
            ((unsigned long long)in.pointInsideTarget << 32) |
            ((unsigned long long)in.hasCellAncestor << 40) |
            ((unsigned long long)in.isKeyWindow << 48);
        unsigned expected = fun_0057efe4(in.nativeActionCount, packed);
        unsigned actual = (unsigned)TSFallbackForInputs(in);
        cases++;
        if (expected != actual) {
            printf("FAIL bits=0x%02x expected=%u actual=%u\n", bits, expected, actual);
            failures++;
        }
    }
    printf("fallback truth table: %d cases, %d failures\n", cases, failures);
    return failures;
}

static int expectClamp(double x, double y, double wantX, double wantY) {
    TSClampContentOffset(&x, &y, 10, 5, 20, 15, 1000, 2000, 300, 400);
    if (fabs(x - wantX) > 1e-9 || fabs(y - wantY) > 1e-9) {
        printf("FAIL clamp got (%g,%g) want (%g,%g)\n", x, y, wantX, wantY);
        return 1;
    }
    return 0;
}

static int testClamp(void) {
    int failures = 0;
    failures += expectClamp(100, 100, 100, 100);    // in range
    failures += expectClamp(-50, -50, -5, -10);     // min is -inset
    failures += expectClamp(5000, 5000, 715, 1620); // max is content - bounds + inset
    // Content smaller than bounds: only the minimum is reachable.
    double x = 40, y = 40;
    TSClampContentOffset(&x, &y, 0, 0, 0, 0, 100, 100, 300, 400);
    if (x != 0 || y != 0) {
        printf("FAIL small content clamp got (%g,%g)\n", x, y);
        failures++;
    }
    printf("content offset clamp: %d failures\n", failures);
    return failures;
}

static int testSlop(void) {
    int failures = 0;
    failures += TSExceedsTapSlop(12, 0) ? 1 : 0;  // exactly 12pt still a tap
    failures += TSExceedsTapSlop(0, -12) ? 1 : 0;
    failures += TSExceedsTapSlop(12.01, 0) ? 0 : 1;
    failures += TSExceedsTapSlop(9, 9) ? 0 : 1;   // 162 > 144
    printf("tap slop: %d failures\n", failures);
    return failures;
}

int main(void) {
    int failures = testFallbackTruthTable() + testClamp() + testSlop();
    printf(failures ? "FAILED\n" : "ALL PASSED\n");
    return failures ? 1 : 0;
}
