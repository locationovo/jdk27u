#!/bin/bash
# 检查JEP 527后量子密钥交换在iOS上的可用性
# TLS握手失败会影响所有HTTPS连接

ROOT="$1"

# 检查ML-KEM-768是否在NamedGroup中注册
NG_FILE="$ROOT/src/java.base/share/classes/sun/security/ssl/NamedGroup.java"
if [ -f "$NG_FILE" ] && grep -q 'ML_KEM_768' "$NG_FILE"; then
    echo "  INFO: ML-KEM-768 registered in NamedGroup"
    
    # 检查是否有原生依赖
    NATIVE_EC="$ROOT/src/jdk.crypto.ec"
    if [ -d "$NATIVE_EC" ]; then
        echo "  INFO: jdk.crypto.ec has native code, verify iOS cross-compile"
    fi
    
    # 检查SunJCE纯Java实现路径
    if grep -rl 'Kyber' "$ROOT/src/java.base/share/classes/sun/security/" 2>/dev/null | grep -q .; then
        echo "  INFO: Pure Java Kyber implementation found (no native dep)"
    else
        echo "  WARN: Kyber may have native dependency, check iOS build"
    fi
else
    echo "  SKIP: ML-KEM-768 not found in NamedGroup (may not be in this JDK build)"
fi

# 检查TLS握手降级逻辑
SSL_DIR="$ROOT/src/java.base/share/classes/sun/security/ssl"
if grep -rl 'ML_KEM\|Kyber\|PQC' "$SSL_DIR" 2>/dev/null | grep -q .; then
    echo "  INFO: PQC-related code found in SSL module"
else
    echo "  INFO: No PQC code in SSL module (iOS safe)"
fi
