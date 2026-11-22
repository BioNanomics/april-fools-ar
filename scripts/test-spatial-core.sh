#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=${AFSC_BUILD_DIR:-"$project_root/build/spatial-core"}
cmake -S "$project_root/native/SpatialCore" -B "$build_dir" \
  -DCMAKE_BUILD_TYPE=Release -DAFSC_BUILD_JNI=ON -DBUILD_TESTING=ON
cmake --build "$build_dir" --parallel
ctest --test-dir "$build_dir" --output-on-failure
cmp "$build_dir/jni-generated/com_aprilfools_spatial_SpatialCore.h" \
  "$project_root/native/SpatialCore/jni/generated/com_aprilfools_spatial_SpatialCore.h"
cmake --install "$build_dir" --prefix "$build_dir/install"
cmake -S "$project_root/robot/cpp" -B "$build_dir/installed-consumer" \
  -DCMAKE_PREFIX_PATH="$build_dir/install"
cmake --build "$build_dir/installed-consumer" --parallel
"$build_dir/installed-consumer/afsc_installed_consumer"
case "$(uname -s)" in
  Darwin) library="$build_dir/libaf_spatial_core.dylib" ;;
  *) library="$build_dir/libaf_spatial_core.so" ;;
esac
AFSC_LIBRARY="$library" python3 -m unittest discover \
  -s "$project_root/scripts/tests" -p test_spatial_core_replay.py
printf '%s\n' "C ABI, JNI, generated header and installation checks passed."
