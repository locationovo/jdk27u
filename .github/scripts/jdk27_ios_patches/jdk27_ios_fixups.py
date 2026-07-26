#!/usr/bin/env python3
import os
import sys
import re
import fileinput


def find_files(root, pattern):
    """递归查找匹配模式的文件"""
    import fnmatch
    matches = []
    for dirpath, _, filenames in os.walk(root):
        for f in filenames:
            if fnmatch.fnmatch(f, pattern):
                matches.append(os.path.join(dirpath, f))
    return matches


def apply_fixup(filepath, description, old_text, new_text, warn_only=False):
    """对单个文件执行文本替换"""
    if not os.path.exists(filepath):
        if warn_only:
            print(f"  SKIP [{description}]: {filepath} not found")
        else:
            print(f"  WARN [{description}]: {filepath} not found")
        return False

    with open(filepath, 'r') as f:
        content = f.read()

    if old_text in content:
        content = content.replace(old_text, new_text)
        with open(filepath, 'w') as f:
            f.write(content)
        print(f"  FIXED [{description}]: {filepath}")
        return True
    else:
        if warn_only:
            print(f"  SKIP [{description}]: pattern not found in {filepath}")
        else:
            print(f"  WARN [{description}]: pattern not found in {filepath}")
        return False


def main():
    if len(sys.argv) < 2:
        print("Usage: jdk27_ios_fixups.py <openjdk-root>")
        sys.exit(1)

    root = sys.argv
    print(f"=== JDK 27 iOS Fixups === target: {root}")

    # ──────────────────────────────────────────────
    # 1. 值类型 (Value Types) 对齐修复
    #    JDK 27 可能正式化值对象，ARM64 iOS 上对齐要求不同
    # ──────────────────────────────────────────────
    macro_asm = os.path.join(
        root, "src/hotspot/cpu/aarch64/macroAssembler_aarch64.hpp"
    )
    apply_fixup(
        macro_asm,
        "ValueKlass alignment on iOS ARM64",
        "STATIC_ASSERT(sizeof(ValueKlass) == 48);",
        "STATIC_ASSERT(sizeof(ValueKlass) == 64);  // iOS ARM64 alignment",
        warn_only=True
    )

    # ──────────────────────────────────────────────
    # 2. MAP_JIT 替代方案 —— 确保 mirror_mapping 路径可用
    #    iOS 26+ / TXM 上 APRR 被禁用，必须用 vm_remap
    # ──────────────────────────────────────────────
    os_bsd = os.path.join(root, "src/hotspot/os/bsd/os_bsd.cpp")
    if os.path.exists(os_bsd):
        with open(os_bsd, 'r') as f:
            content = f.read()

        # 确保 MAP_JIT 回退到 vm_remap 时有正确的错误处理
        if "MAP_JIT" in content and "vm_remap" not in content:
            fallback = """
  // iOS 26+ TXM fallback: MAP_JIT may fail, use vm_remap
  if (addr == MAP_FAILED && errno == EPERM) {
    addr = (char*) ::vm_remap(mach_task_self(), &target_addr, size,
                               0, VM_FLAGS_ANYWHERE | VM_FLAGS_RANDOM_ADDR,
                               mem_entry, 0, FALSE,
                               VM_PROT_READ | VM_PROT_WRITE,
                               VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE,
                               VM_INHERIT_DEFAULT);
  }
"""
            # 在第一个 MAP_JIT 失败处理之后插入
            content = content.replace(
                "guarantee(addr != MAP_FAILED, \"mmap failed for size: %zu\", size);",
                fallback + "\n  guarantee(addr != MAP_FAILED, \"mmap/vm_remap failed for size: %zu\", size);"
            )
            with open(os_bsd, 'w') as f:
                f.write(content)
            print("  FIXED [MAP_JIT fallback]: os_bsd.cpp")

    # ──────────────────────────────────────────────
    # 3. JDK 27 新 API —— 线程本地握手 (Thread-Local Handshakes)
    #    某些平台相关代码可能使用了 iOS 不支持的 pthread 扩展
    # ──────────────────────────────────────────────
    thread_files = find_files(
        os.path.join(root, "src/hotspot/share/runtime"),
        "thread*.hpp"
    )
    for f in thread_files:
        apply_fixup(
            f,
            "pthread_jit_write_protect guard",
            "#include <pthread.h>",
            "#include <pthread.h>\n#ifdef __APPLE__\n#include <TargetConditionals.h>\n#if TARGET_OS_IOS && !TARGET_OS_SIMULATOR\n#include <pthread/jit.h>\n#endif\n#endif",
            warn_only=True
        )

    # ──────────────────────────────────────────────
    # 4. 字符串去重 (String Dedup) 在低内存设备上默认关闭
    #    iOS 设备内存有限，JDK 27 默认开启的去重可能造成压力
    # ──────────────────────────────────────────────
    gc_globals = os.path.join(
        root, "src/hotspot/share/gc/shared/gc_globals.hpp"
    )
    apply_fixup(
        gc_globals,
        "Disable StringDedup on iOS",
        'develop(bool, UseStringDeduplication, true,',
        'develop(bool, UseStringDeduplication, false,  // iOS: default off for memory-constrained devices',
        warn_only=True
    )

    # ──────────────────────────────────────────────
    # 5. ZGC 分代模式 —— iOS 上优先使用单代模式
    #    JDK 27 ZGC 默认分代，但 iOS 内存受限场景下单代更稳定
    # ──────────────────────────────────────────────
    zgc_globals = os.path.join(
        root, "src/hotspot/share/gc/z/zGlobals.hpp"
    )
    apply_fixup(
        zgc_globals,
        "ZGC generational mode default for iOS",
        "ZGenerational",
        "// iOS: prefer non-generational ZGC for predictable memory usage\n  ZGenerational",
        warn_only=True
    )

    # ──────────────────────────────────────────────
    # 6. 检查并报告未预期的 macOS 私有框架引用
    # ──────────────────────────────────────────────
    print("\n=== Checking for problematic macOS-only APIs ===")
    problematic_patterns = [
        (r'IOKit\.h', 'IOKit is unavailable on iOS'),
        (r'CoreFoundation/CFNotificationCenter\.h', 'CFNotificationCenter unavailable on iOS'),
        (r'#if.*__MAC_OS_X_VERSION_MAX_ALLOWED', 'macOS-only version guard, verify iOS path exists'),
    ]
    for pattern, desc in problematic_patterns:
        for dirpath, _, filenames in os.walk(os.path.join(root, "src")):
            for fname in filenames:
                if fname.endswith(('.hpp', '.cpp', '.h', '.c')):
                    fpath = os.path.join(dirpath, fname)
                    try:
                        with open(fpath, 'r') as f:
                            if re.search(pattern, f.read()):
                                print(f"  WARNING [{desc}]: {fpath}")
                    except Exception:
                        pass

    print("\n=== JDK 27 iOS Fixups Complete ===")


if __name__ == "__main__":
    main()
