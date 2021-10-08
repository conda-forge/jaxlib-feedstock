#!/bin/bash

set -euxo pipefail

if [[ "${target_platform}" == osx-* ]]; then
  export LDFLAGS="${LDFLAGS} -lz -framework CoreFoundation -Xlinker -undefined -Xlinker dynamic_lookup"
else
  export LDFLAGS="${LDFLAGS} -lrt"
fi

# from bazel-toolchain-feedstock
export TARGET_SYSTEM="${HOST}"
if [[ "${target_platform}" == "osx-64" ]]; then
  export TARGET_LIBC="macosx"
  export TARGET_CPU="darwin_x86_64"
  export TARGET_SYSTEM="x86_64-apple-macosx"
elif [[ "${target_platform}" == "osx-arm64" ]]; then
  export TARGET_LIBC="macosx"
  export TARGET_CPU="darwin_arm64"
  export TARGET_SYSTEM="arm64-apple-macosx"
elif [[ "${target_platform}" == "linux-64" ]]; then
  export TARGET_LIBC="unknown"
  export TARGET_CPU="k8"
elif [[ "${target_platform}" == "linux-aarch64" ]]; then
  export TARGET_LIBC="unknown"
  export TARGET_CPU="aarch64"
elif [[ "${target_platform}" == "linux-ppc64le" ]]; then
  export TARGET_LIBC="unknown"
  export TARGET_CPU="ppc"
fi

CUSTOM_BAZEL_OPTIONS="--bazel_options=--bazel_options=--logging=6 --bazel_options=--verbose_failures --bazel_options=--toolchain_resolution_debug"

if [[ "${target_platform}" == "osx-64" ]]; then
  # Tensorflow doesn't cope yet with an explicit architecture (darwin_x86_64) on osx-64 yet.
  TARGET_CPU=darwin
fi

if [[ "${target_platform}" == "osx-arm64" ]]; then
  ${PYTHON} build/build.py --target_cpu_features default --enable_mkl_dnn ${CUSTOM_BAZEL_OPTIONS} --target_cpu ${TARGET_CPU}
else
  ${PYTHON} build/build.py --target_cpu_features default --enable_mkl_dnn ${CUSTOM_BAZEL_OPTIONS} --bazel_options=--cpu --bazel_options=${TARGET_CPU}
fi

# Clean up to speedup postprocessing
pushd build
bazel clean
popd

${PYTHON} -m pip install dist/jaxlib-*.whl
