#!/bin/bash
# iOS内存受限，JDK 27默认开启的StringDedup会额外消耗内存
# 性能优化项，不影响功能

TARGET="$1/src/hotspot/share/gc/shared/gc_globals.hpp"
[ ! -f "$TARGET" ] && echo "  SKIP: $TARGET not found" && exit 0

OLD='develop(bool, UseStringDeduplication, true,'
NEW='develop(bool, UseStringDeduplication, false,  // iOS: default off for memory-constrained devices'

if grep -q "$OLD" "$TARGET"; then
    sed -i '' "s|$OLD|$NEW|" "$TARGET"
    echo "  FIXED: StringDedup default → false"
else
    echo "  SKIP: pattern not found (may already be false)"
fi
