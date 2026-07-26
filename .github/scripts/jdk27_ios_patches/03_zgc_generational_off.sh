#!/bin/bash
# iOS设备内存有限，ZGC分代模式额外开销可能导致OOM
TARGET="$1/src/hotspot/share/gc/z/zGlobals.hpp"
[ ! -f "$TARGET" ] && echo "  SKIP: $TARGET not found" && exit 0

# 在ZGenerational定义处添加注释，提醒iOS上默认关闭
if grep -q 'ZGenerational' "$TARGET" && ! grep -q 'iOS: prefer non-generational' "$TARGET"; then
    sed -i '' 's/ZGenerational/\/\/ iOS: prefer non-generational ZGC for predictable memory usage\n  ZGenerational/' "$TARGET"
    echo "  FIXED: ZGC generational annotation added"
else
    echo "  SKIP: already annotated or pattern not found"
fi
