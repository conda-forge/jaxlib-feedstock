#!/bin/bash

set -euxo pipefail

if [[ "${target_platform}" == osx-* ]]; then
  export LDFLAGS="${LDFLAGS} -lz -framework CoreFoundation -Xlinker -undefined -Xlinker dynamic_lookup"
else
  export LDFLAGS="${LDFLAGS} -lrt"
fi
source ${RECIPE_DIR}/gen-bazel-toolchain.sh

CUSTOM_BAZEL_OPTIONS="--crosstool_top=//custom_toolchain:toolchain --logging=6 --verbose_failures"

if [[ "${target_platform}" == "osx-64" ]]; then
  # Tensorflow doesn't cope yet with an explicit architecture (darwin_x86_64) on osx-64 yet.
  TARGET_CPU=darwin
fi

if [[ "${target_platform}" == "osx-arm64" ]]; then
  ${PYTHON} build/build.py --target_cpu_features default --enable_mkl_dnn --bazel_options " ${CUSTOM_BAZEL_OPTIONS}" --target_cpu ${TARGET_CPU}
else
  ${PYTHON} build/build.py --target_cpu_features default --enable_mkl_dnn --bazel_options " ${CUSTOM_BAZEL_OPTIONS} --cpu ${TARGET_CPU}"
fi
${PYTHON} -m pip install dist/jaxlib-*.whl
