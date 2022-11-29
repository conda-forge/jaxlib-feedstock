#!/bin/bash

set -euxo pipefail

if [[ "${target_platform}" == osx-* ]]; then
  export LDFLAGS="${LDFLAGS} -lz -framework CoreFoundation -Xlinker -undefined -Xlinker dynamic_lookup"
else
  export LDFLAGS="${LDFLAGS} -lrt"
fi


CUSTOM_BAZEL_OPTIONS="--bazel_options=--logging=6 --bazel_options=--verbose_failures --bazel_options=--toolchain_resolution_debug"

echo "Building...."
${PYTHON} build/build.py --target_cpu_features default --enable_mkl_dnn ${CUSTOM_BAZEL_OPTIONS}
echo "Building done."

# Clean up to speedup postprocessing
echo "Issuing bazel clean..."
pushd build
bazel clean
popd

echo "Issuing bazel shutdown..."
bazel shutdown

echo "Installing jaxlib wheel..."
${PYTHON} -m pip install dist/jaxlib-*.whl
