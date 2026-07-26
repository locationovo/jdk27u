#!/bin/bash
# 修复ValueKlass在iOS上的对齐（48 to 64字节）
# 值类型正式化，HotSpot核心变更

TARGET="$1/src/hotspot/cpu/aarch64/macroAssembler_aarch64.hpp"
[ ! -f "$TARGET" ] && echo "  SKIP: $TARGET not found" && exit 0

if grep -q 'STATIC_ASSERT(sizeof(ValueKlass) == 48);' "$TARGET"; then
    sed -i '' 's/STATIC_ASSERT(sizeof(ValueKlass) == 48);/STATIC_ASSERT(sizeof(ValueKlass) == 64);  \/\/ iOS ARM64 alignment/' "$TARGET"
    echo "  FIXED: ValueKlass alignment 48→64"
else
    echo "  SKIP: ValueKlass pattern not found (already fixed or different version)"
fi
