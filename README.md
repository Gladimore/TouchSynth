# TouchSynth

In-process touch synthesis for iOS, reimplemented from the replay engine in iGameGod 0.8.3. Give it screen coordinates and it creates real `UITouch` and `UIEvent` objects, then delivers them to the view under that point. See [docs/REVERSING.md](docs/REVERSING.md) for how the original works and where this differs from it.

**Scope:** it only reaches windows in the process it runs in, so link it into your app or inject it into the target. It can't touch SpringBoard or other apps, and it doesn't create HID events.

**Status:** this has never run on a device. The logic tests pass and the sources compile for `arm64-apple-ios14.0`, but only against the hand-written headers in `tools/stub-sdk`. See [What has been verified](#what-has-been-verified).

## Install

**Swift Package Manager**, for an Xcode app or framework. Add this local package, then `import TouchSynth`:

```swift
.package(path: "../TouchSynth")
```

**Theos**, for a tweak or a standalone dylib. Run `make` here to get `libTouchSynth.dylib`, or add the sources to your own tweak:

```make
MyTweak_FILES += $(wildcard TouchSynth/Sources/TouchSynth/*.m) TouchSynth/Sources/TouchSynth/TSTouchLogic.c
MyTweak_CFLAGS += -fobjc-arc -ITouchSynth/Sources/TouchSynth -ITouchSynth/Sources/TouchSynth/include
```

The library has no Objective-C categories or `+load` methods and prefixes its symbols. It needs no `-ObjC` flag and won't collide with iGameGod or your older `TouchSynthesis.dylib` if they're loaded in the same process.

## Use

Points are in screen coordinates (`UIScreen.coordinateSpace`). Every call is safe from any thread; calls made off the main thread are queued to it in order.

```swift
import TouchSynth

let synth = TSTouchSynthesizer.shared

synth.tap(at: CGPoint(x: 200, y: 400))

synth.swipe(from: CGPoint(x: 200, y: 600), to: CGPoint(x: 200, y: 200), duration: 0.3) { finished in
    print("swipe finished: \(finished)")
}

// Manual control, one identifier per finger
synth.touchDown(withIdentifier: 1, at: CGPoint(x: 100, y: 100))
synth.touchMove(withIdentifier: 1, to: CGPoint(x: 150, y: 100))
synth.touchUp(withIdentifier: 1, at: CGPoint(x: 150, y: 100))

synth.cancelAllTouches()
```

```objc
#import "TouchSynth.h"

[TSTouchSynthesizer.sharedSynthesizer tapAtPoint:CGPointMake(200, 400)];
```

```c
// C, for engines and FFI
TSTap(200, 400);
TSSwipe(200, 600, 200, 200, 0.3);
TSTouchDown(1, 100, 100);
TSTouchUp(1, 100, 100);
```

The Swift names above are what the importer should derive from the headers. No Swift has been compiled against them, so check them in Xcode if one doesn't resolve.

To keep your own overlay out of the way, set `synth.excludedView = overlay`. It's never hit-tested, and its interaction is turned off while events are dispatched.

## First run on a new iOS version

This depends on private UIKit details, so check them first:

```swift
TSTouchSynthesizer.runtimeDiagnostics().forEach { print($0.key, $0.value) }
synth.verboseLogging = true
```

| Diagnostic is NO | What it means |
| --- | --- |
| `event._initWithEvent:touches:` | No `UIEvent` can be built, so `sendEvent:` is skipped. Direct delivery still runs, with a nil event. |
| any of `touch._tapCount`, `_locationInWindow`, `_previousLocationInWindow`, `_phase`, `_touchFlags`, `_timestamp` | Touches can't be created and `sendEvent` returns `NO`. |
| `touch.setWindow:` or `touch.setView:` | Falls back to the `_setWindow:` / `_setView:` style setters, then the raw ivar, then KVC. |

## Delivery stages

These run in order, and `deliveryOptions` can turn any of them off:

| Option | Runs when | What it does |
| --- | --- | --- |
| `TSDeliverySendEvent` | every phase | `[window sendEvent:]` with a `UITouchesEvent` |
| `TSDeliveryDirectTouches` | no `UIControl` ancestor, or `sendEvent:` didn't run | calls `touchesBegan:` etc. on the hit view |
| `TSDeliveryScrollViews` | moved past 12pt, no native scroll | sets `contentOffset` on the nearest scroll view |
| `TSDeliveryPanGestures` | moved past 12pt | runs the targets of app-owned pan recognizers |
| `TSDeliveryControlActions` | ended on a control | `sendActionsForControlEvents:`, unless UIKit already fired |
| `TSDeliveryTapGestures` | ended as a tap | runs the targets of app-owned tap recognizers |
| `TSDeliveryCellSelection` | ended on a cell in a non-key window | selects the cell and calls the delegate |

**Possible double delivery:** this comes from iGameGod. A view without a control ancestor gets both `sendEvent:` and direct `touches*` calls, on the assumption that `sendEvent:` doesn't reach it. If a view registers each touch twice, try `synth.deliveryOptions = TSDeliveryOptions.all.subtracting(.directTouches)`, or drop `.sendEvent` instead. That's the first setting to change for Unity-style views.

Multi-touch is separate events: each `UIEvent` holds one touch, so a view asking `event.allTouches` for two fingers sees one.

## What has been verified

Run `tools/check.sh <scratch-dir>` on any machine with clang.

| Check | Result |
| --- | --- |
| Fallback decision vs. decompiled `FUN_0057efe4`, all 256 input combinations | matches |
| Content-offset clamp and tap slop tests | pass |
| All sources compile for `arm64-apple-ios14.0` with `-Wall -Wextra -Werror` | pass, stub headers only |
| `TSGSEventProxy` ivar offsets vs. iGameGod's class metadata | match |
| Private selectors used vs. strings in the iGameGod binary | all present |
| `Package.swift` parses | pass |
| Built with Apple's SDK, with Theos, or linked | **not done:** no iOS SDK here, and this machine's `ld64.lld` refuses Apple platforms |
| Touches actually reach a view on a device | **not done** |
