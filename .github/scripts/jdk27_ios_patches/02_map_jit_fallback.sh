#!/bin/bash
# iOS 26+ APRR被禁用时，MAP_JIT 可能失败，回退到vm_remap
# JIT代码缓存分配失败会导致JVM无法运行

TARGET="$1/src/hotspot/os/bsd/os_bsd.cpp"
[ ! -f "$TARGET" ] && echo "  SKIP: $TARGET not found" && exit 0

# 检查是否已有vm_remap回退代码
if grep -q 'vm_remap' "$TARGET"; then
    echo "  SKIP: vm_remap fallback already present"
    exit 0
fi

# 在MAP_JIT失败处理之后插入回退逻辑
GUARD='guarantee(addr != MAP_FAILED, "mmap failed for size: %zu", size);'
FALLBACK='  // iOS 26+ TXM fallback: MAP_JIT may fail, use vm_remap\
  if (addr == MAP_FAILED \&\& errno == EPERM) {\
    addr = (char*) ::vm_remap(mach_task_self(), \&target_addr, size,\
                               0, VM_FLAGS_ANYWHERE | VM_FLAGS_RANDOM_ADDR,\
                               mem_entry, 0, FALSE,\
                               VM_PROT_READ | VM_PROT_WRITE,\
                               VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE,\
                               VM_INHERIT_DEFAULT);\
  }\
  guarantee(addr != MAP_FAILED, "mmap/vm_remap failed for size: %zu", size);'

if grep -q "$GUARD" "$TARGET"; then
    sed -i '' "s|$GUARD|$FALLBACK|" "$TARGET"
    echo "  FIXED: MAP_JIT vm_remap fallback inserted"
else
    echo "  WARN: MAP_JIT guard pattern not found, manual check needed"
fi
