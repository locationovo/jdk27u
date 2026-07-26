#!/bin/bash
# iOS特有API（pthread_jit_write_protect）需要pthread/jit.h
# 缺失会导致编译错误，但不影响非JIT路径

ROOT="$1"
HEADER_GUARD='#include <pthread.h>'
JIT_INCLUDE='#include <pthread.h>\
#ifdef __APPLE__\
#include <TargetConditionals.h>\
#if TARGET_OS_IOS \&\& !TARGET_OS_SIMULATOR\
#include <pthread/jit.h>\
#endif\
#endif'

for f in $(find "$ROOT/src/hotspot/share/runtime" -name 'thread*.hpp' 2>/dev/null); do
    if grep -q "$HEADER_GUARD" "$f" && ! grep -q 'pthread/jit.h' "$f"; then
        sed -i '' "s|$HEADER_GUARD|$JIT_INCLUDE|" "$f"
        echo "  FIXED: pthread/jit.h added to $(basename $f)"
    fi
done
