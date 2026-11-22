#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) host=arm64-apple-darwin; sha=12a3b4feaf48b6567b1b85274b856b423103035c297cd50b31b31e1b74a275c8 ;;
  Darwin-x86_64) host=x86_64-apple-darwin; sha=b63b5b2165ea81686c05e2abe483b02293a98bfd6ce72690d74c864833028dbc ;;
  Linux-x86_64) host=x86_64-linux-gnu; sha=992d4f2037762588c062f5b22f282b92b9143a2e8cb39a2027e67249c8ed5bea ;;
  Linux-aarch64) host=aarch64-trixie-linux-gnu; sha=91eb185ee07efa58b16d03076e1d96afb3b551a3cc80f7195b573a3427790b3b ;;
  *) printf '%s\n' 'Unsupported toolchain host; use a pinned OpenSDK v2027-1 release.' >&2; exit 1 ;;
esac
toolchain=${AFSC_SYSTEMCORE_TOOLCHAIN:-"$root/build/toolchains/opensdk-v2027-1-$host/systemcore"}
if [ ! -f "$toolchain/toolchain-config.cmake" ]; then
  cache="$root/build/toolchains/opensdk-v2027-1-$host"
  mkdir -p "$cache"
  archive="$cache/toolchain.tgz"
  curl -fL --retry 2 "https://github.com/wpilibsuite/opensdk/releases/download/v2027-1/arm64-systemcore-2027-$host-Toolchain-14.3.0.tgz" -o "$archive"
  python3 - "$archive" "$sha" <<'PY'
import hashlib, pathlib, sys
if hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest() != sys.argv[2]:
    raise SystemExit('OpenSDK checksum mismatch')
PY
  tar -xzf "$archive" -C "$cache"
fi
if [ -z "${JAVA_HOME:-}" ]; then
  if [ "$(uname -s)" = Darwin ]; then
    JAVA_HOME=$(/usr/libexec/java_home)
  else
    JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")
  fi
fi
export JAVA_HOME
case "$(uname -s)" in Darwin) jni_os=darwin ;; *) jni_os=linux ;; esac
for type in Release Debug; do
  dir="$root/build/systemcore-$type"
  cmake -S "$root/native/SpatialCore" -B "$dir" \
    -DCMAKE_TOOLCHAIN_FILE="$toolchain/toolchain-config.cmake" \
    -DCMAKE_BUILD_TYPE="$type" -DBUILD_TESTING=OFF -DAFSC_BUILD_JNI=ON \
    -DAFSC_JNI_INCLUDE_DIRS="$JAVA_HOME/include;$JAVA_HOME/include/$jni_os"
  cmake --build "$dir" --parallel
done
python3 "$root/robot/package-maven.py" --release-build "$root/build/systemcore-Release" \
  --debug-build "$root/build/systemcore-Debug"
printf '%s\n' "Built Systemcore GCC 14.3 native and JNI artifacts. No device code was executed."
