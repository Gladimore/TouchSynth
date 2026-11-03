# How iGameGod synthesizes touches

Source: `iGameGod.framework/iGameGod` from `com.gamegod.igg_0.8.3`, using the Ghidra export `iGameGod.c` and `llvm-objdump` on the binary. Addresses are file offsets in that binary. Line numbers refer to `iGameGod.c`.

The base is the old `UITouch (Synthesize)` / `UIEvent (Synthesize)` / `GSEventProxy` technique. Those names and the proxy's layout match the widely copied public pattern (for example in KIF). iGameGod's Swift replay engine, `Plugin_TouchReplay`, wraps it in fallbacks.

## Building a touch

`-[UITouch(Synthesize) initInView:at:withCount:]` (line 124463) calls `-[UITouch init]`, then writes private ivars found by name:

| Ivar | Value |
| --- | --- |
| `_tapCount` | count |
| `_locationInWindow`, `_previousLocationInWindow` | the window point |
| `_phase` | 0 (began) |
| `_touchFlags` | `\|= 3`: bit 0 first touch for view, bit 1 is-tap. 16-bit read-modify-write at `0xa0e78` |
| `_timestamp` | `NSProcessInfo.systemUptime` |
| `_window`, `_view` | set with a fallback chain (below) |
| `_touchIdentifier` | set later, 64-bit write at `0xa0df4` |

Window and view go through `object_setIvar`, then `_setWindow:`, `setWindow:`, then KVC, with a read-back between each. Both are also stored as associated objects. `+load` swizzles `-[UITouch view]` and `-[UITouch window]` to return those when the real value is nil.

Moving (`setLocationInWindow:`, line 124775) copies the current location to previous, and clears the tap flag if either axis moved more than 2pt.

## Building an event

`-[UIEvent(Synthesize) initWithTouch:]` (`0xa19dc`) fills a fake GSEvent and calls `-[UITouchesEvent _initWithEvent:touches:]`:

| Offset | Field | Value |
| --- | --- | --- |
| `0x08` | flags | `0x1010180` when the phase is ended or cancelled, otherwise `0x3010180` |
| `0x0c` | type | `0xbb9` (3001) |
| `0x14` | x1, y1 | current location |
| `0x1c` | x2, y2 | previous location |
| `0x68` | sizeX, sizeY | 1.0, 1.0 |
| `0x70` | x3, y3 | current location |

Instance size is 132 bytes. All coordinates are in window space, stored as floats. The event's `_timestamp` ivar is then overwritten with the current uptime.

## Input format

`Plugin_TouchReplay.TouchEvent` (line 7685): `id`, `action` (0 began, 1 moved, 2 ended, 3 cancelled), `x`, `y` in screen space, `time`, plus `windowRuntimeID`, `windowClassName` and `windowLevel` as hints.

## Finding the target

| Function | Purpose |
| --- | --- |
| `FUN_0058e2d8` | Windows whose scene is foreground active or inactive, or has no scene |
| `FUN_00588dd8` | Eligible: not hidden, alpha > 0.01, interaction on, non-zero size, not an overlay |
| `FUN_005883e8` | Picks a window from the runtime ID hint, else the class name and level hints |
| `FUN_00588efc` | Fallback order: higher level, then key window, then later in `windows` (comparator near line 1165668) |
| `FUN_00588c54` | Hit test with the exclusion view disabled. A hit on the window itself, or inside the exclusion view, counts as nothing |
| `FUN_00589594` | A window showing only the exclusion view is treated as an overlay |
| `FUN_00587fb4` | Later phases keep the current window if it still qualifies, else search again |

## Delivery chain

`FUN_00584b84` (line 1160040) handles each event:

1. Ended or cancelled: start tracking the nearest `UIControl` with its count at 0. A swizzle of `-[UIApplication sendAction:to:from:forEvent:]` (`gg_touchReplay_…`, `FUN_00589a98`) increments the count, which shows whether UIKit really fired the control.
2. Create the event and call `[window sendEvent:]`, with the exclusion view's interaction turned off. If there's no window, it uses `[UIApplication sendEvent:]`.
3. Call `touches*:withEvent:` on the hit view directly (`FUN_0058eb90`) if the event couldn't be created or dispatched, **or the touch has no control ancestor**.
4. Moved, no control, past 12pt, and the scroll view's offset didn't change by more than 0.5: set `contentOffset` to the start offset minus the delta, clamped (`FUN_0058ed7c`), and update the pan's translation.
5. Past 12pt with no control: run app-owned pan recognizers (`FUN_0058dda0`). Moved is state 1, then 2. Ended is 3, or 1 then 3 if the pan never started. Cancelled is 4.
6. Ended: run the tap fallback below.
7. Ended or cancelled: stop tracking and forget the touch.

### Tap fallback

`FUN_00587624` gathers facts about the touch and `FUN_0057efe4` turns them into a decision. Readable form, tested exhaustively against the original in `Tests/logic_test.c`:

```
native action count != 0, or point outside target  -> none
control with targets                               -> 1 fire control actions
not a tap (moved past 12pt)                        -> none
has a control, or no cell ancestor:
    has tap gestures                               -> 2 tap gestures
    otherwise                                      -> 3 direct tap
cell ancestor, no control:
    key window                                     -> none
    otherwise                                      -> 4 select cell
```

| Result | Function | Action |
| --- | --- | --- |
| 1 | `FUN_0058fa48` | Sends `TouchUpInside`, then `ValueChanged` and `PrimaryActionTriggered` while the count is still 0 |
| 2 | `FUN_0058fb74` | Runs tap recognizer targets. If none ran and the target is safe, does result 3 |
| 3 | `FUN_0058fe74` | A new touch and a began/ended pair, sent straight to the view. Skipped if step 3 above already delivered |
| 4 | `FUN_00590220`, `FUN_00590528` | Collection or table view selection, including delegate calls |

Recognizers are invoked by forcing `state` with KVC, calling each `_targets` entry through `sendAction:to:from:forEvent:`, then restoring `state`. They're skipped if the recognizer or a target looks like WebKit, or a target's bundle is outside the app and under `/System/Library/` or `/PrivateFrameworks/`.

`FUN_0058442c` cancels everything: a cancelled phase, pan cancel if active, `sendEvent:`, then a direct `touchesCancelled:`.

## Differences from iGameGod

**Behavior changes, each to avoid a crash or a stuck state:**

| Change | Why |
| --- | --- |
| Setters run before the raw ivar | `object_setIvar` doesn't retain on a non-ARC ivar. If `UITouch` is non-ARC and releases `_view` in `dealloc`, that over-releases. Not confirmed either way, and setters are safe in both cases. |
| Writes are verified through the ivar | The hooked getters return the fallback, so reading through them reports success even when the write failed. |
| Integer ivars are sized from their type encoding | iGameGod writes `_touchIdentifier` as 64 bits, which would overwrite the next ivar if UIKit declares it narrower. |
| `_initWithEvent:touches:` is checked first, and wrapped in `@try` | iGameGod calls it unguarded, so a removed selector would crash the host. |
| Pans also run while active, not only past 12pt | iGameGod never sends the end state if the finger finishes near where it started. |

**Packaging changes:** no categories, `+load` or `gg_` selectors. Hooks use `method_setImplementation` on C functions and install on first use, and `GSEventProxy` is now `TSGSEventProxy`.

**Left out:**

- The recorder (`gg_touchRecorder_sendEvent:`) and the timed replay UI.
- The `windowRuntimeID` hint, which only matches within one session.
- The check that skips windows from iGameGod's own bundle. `excludedView` covers the same need.
- The private selection selectors tried first in `FUN_0057f048` and `FUN_0057f52c`. Only the public-API path is here.
- The `withCount:` tap count parameter. It's always 1.
