#!/bin/bash

set -euxo pipefail

if [[ "${target_platform}" == osx-* ]]; then
  export LDFLAGS="${LDFLAGS} -lz -framework CoreFoundation -Xlinker -undefined -Xlinker dynamic_lookup"
else
  export LDFLAGS="${LDFLAGS} -lrt"
fi


CUSTOM_BAZEL_OPTIONS="--bazel_options=--logging=6 --bazel_options=--verbose_failures --bazel_options=--toolchain_resolution_debug"

${PYTHON} build/build.py --target_cpu_features default --enable_mkl_dnn ${CUSTOM_BAZEL_OPTIONS}

# Clean up to speedup postprocessing
pushd build
bazel clean
popd

${PYTHON} -m pip install dist/jaxlib-*.whl
