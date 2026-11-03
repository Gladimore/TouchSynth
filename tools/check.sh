#!/bin/sh
# Host checks that need no iOS SDK or device. Needs clang and llvm-nm on PATH.
#   1. Logic tests, run natively against the decompiled originals.
#   2. Compile every source for arm64-apple-ios14.0 against tools/stub-sdk.
#   3. GSEventProxy layout matches the offsets recovered from iGameGod.
# This does not link, and it cannot show that touches reach a view.
# Usage: tools/check.sh <scratch-dir>
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?usage: check.sh <scratch-dir>}"
SRC="$ROOT/Sources/TouchSynth"
STUB="$ROOT/tools/stub-sdk"
mkdir -p "$OUT"

echo "== logic tests"
clang -I "$SRC" "$ROOT/Tests/logic_test.c" "$SRC/TSTouchLogic.c" -o "$OUT/logic_test.exe"
"$OUT/logic_test.exe"

echo "== compile for iOS"
FLAGS="-target arm64-apple-ios14.0 -fobjc-arc -fblocks -Os -isystem $STUB -I $SRC -I $SRC/include"
FLAGS="$FLAGS -Wall -Wextra -Werror -Wno-unused-parameter -Wno-darwin-sdk-settings -Wno-incompatible-sysroot"
for file in TSTouchLogic.c TSPrivateUIKit.m TSTouchSynthesizer.m; do
    clang $FLAGS -c "$SRC/$file" -o "$OUT/$file.o"
    echo "ok $file"
done

echo "== GSEventProxy ivar offsets"
clang $FLAGS -S "$SRC/TSPrivateUIKit.m" -o "$OUT/private.s"
awk '
    /^_OBJC_IVAR_\$_TSGSEventProxy\./ { split($1, a, "."); name = a[2]; sub(":", "", name); getline; print name, $2 }
' "$OUT/private.s" > "$OUT/offsets.txt"
expected="flags 8
type 12
ignored1 16
x1 20
y1 24
x2 28
y2 32
ignored2 36
ignored3 76
sizeX 104
sizeY 108
x3 112
y3 116
ignored4 120"
if [ "$(tr -d '\r' < "$OUT/offsets.txt")" = "$expected" ]; then
    echo "ok, matches iGameGod"
else
    echo "MISMATCH:"
    cat "$OUT/offsets.txt"
    exit 1
fi
