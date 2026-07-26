#!/bin/bash
set -e
. setdevkitpath.sh

export JDK_DEBUG_LEVEL=release

if [[ "$BUILD_IOS" != "1" ]]; then
  # 原版保留
  if [[ -d $NDK ]]; then
    echo "NDK already installed."
  else
    wget -nc -nv -O android-ndk-$NDK_VERSION-linux-x86_64.zip \
      "https://dl.google.com/android/repository/android-ndk-$NDK_VERSION-linux-x86_64.zip"
    ./extractndk.sh
  fi
  ./maketoolchain.sh
else
  # iOS

  chmod +x ios-arm64-clang 2>/dev/null || true
  chmod +x ios-arm64-clang++ 2>/dev/null || true
  chmod +x macos-host-cc 2>/dev/null || true

  export SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
  export MIN_IOS="${MIN_IOS:-15.0}"
  export CC="$(xcrun --sdk iphoneos --find clang) -arch arm64 -isysroot $SDK_PATH -mios-version-min=$MIN_IOS"
  export CXX="$(xcrun --sdk iphoneos --find clang++) -arch arm64 -isysroot $SDK_PATH -mios-version-min=$MIN_IOS"
  export CFLAGS="-isysroot $SDK_PATH -mios-version-min=$MIN_IOS"
  export CXXFLAGS="-isysroot $SDK_PATH -mios-version-min=$MIN_IOS"
  export LDFLAGS="-isysroot $SDK_PATH -mios-version-min=$MIN_IOS"

  echo "=== iOS SDK: $SDK_PATH ==="
  echo "=== CC: $(xcrun --sdk iphoneos --find clang) ==="

  ln -sf .. openjdk-27
fi

# 公共流程

./getlibs.sh
./buildlibs.sh

if [[ "$BUILD_IOS" == "1" ]]; then
  echo "=== Running iOS JDK fixups ==="
  FIXUP_DIR="../scripts/jdk27_ios_patches"
  if [ -d "$FIXUP_DIR" ]; then
    for script in "$FIXUP_DIR"/*.sh; do
      echo "  [fixup] $(basename "$script")"
      bash "$script" openjdk-27 || echo "  WARN: $(basename "$script") failed, continuing"
    done
  else
    echo "  WARN: fixup directory not found: $FIXUP_DIR"
  fi
else
  ./clonejdk.sh
fi

./buildjdk.sh
./removejdkdebuginfo.sh

# 签名
if [[ "$BUILD_IOS" == "1" ]]; then
  echo "=== iOS post-build: signing ==="
  JRE_DIR=$(find build -type d -path "*/images/jre" 2>/dev/null | head -1)
  if [ -n "$JRE_DIR" ]; then
    echo "  Signing all binaries in $JRE_DIR..."
    find "$JRE_DIR" -type f $ -perm +111 -o -name '*.dylib' -o -name '*.so' $ \
      -exec ldid -S {} \; 2>/dev/null || echo "  WARN: ldid not found, skipping sign"
  else
    echo "  WARN: JRE image not found, skipping sign"
  fi
fi

./tarjdk.sh
