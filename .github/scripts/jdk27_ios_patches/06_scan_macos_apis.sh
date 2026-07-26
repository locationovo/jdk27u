#!/bin/bash
# 扫描JDK 27源码中是否引用了iOS不可用的macOS私有框架
# 编译能过但运行时可能崩溃

ROOT="$1"
echo "  === Scanning for macOS-only APIs ==="

# IOKit：iOS不可用
IOKIT=$(grep -rl 'IOKit\.h' "$ROOT/src/" 2>/dev/null | wc -l | tr -d ' ')
[ "$IOKIT" -gt 0 ] && echo "  WARN: $IOKIT files reference IOKit.h (unavailable on iOS)"

# CFNotificationCenter：iOS不可用
CFNOTIFY=$(grep -rl 'CFNotificationCenter\.h' "$ROOT/src/" 2>/dev/null | wc -l | tr -d ' ')
[ "$CFNOTIFY" -gt 0 ] && echo "  WARN: $CFNOTIFY files reference CFNotificationCenter.h"

# macOS 版本守卫：需确认有iOS分支
MAC_GUARD=$(grep -rl '__MAC_OS_X_VERSION_MAX_ALLOWED' "$ROOT/src/" 2>/dev/null)
if [ -n "$MAC_GUARD" ]; then
    echo "  INFO: macOS version guards found, verifying iOS fallback paths..."
    for f in $MAC_GUARD; do
        grep -q '__IPHONE_OS' "$f" || echo "  WARN: $f has macOS guard but no iOS path"
    done
fi

echo "  === macOS API scan complete ==="
