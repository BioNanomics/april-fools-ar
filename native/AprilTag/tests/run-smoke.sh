#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
test_output="$project_root/native/AprilTag/tests/.build"
mkdir -p "$test_output"
cd "$project_root"
clang -std=gnu11 -O2 -pthread -I native/AprilTag -I third_party/apriltag \
  native/AprilTag/AFTagCore.c native/AprilTag/tests/AFTagCoreSmoke.c \
  third_party/apriltag/*.c third_party/apriltag/common/*.c \
  -lm -o "$test_output/af-tag-core-smoke"
"$test_output/af-tag-core-smoke"
