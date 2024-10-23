#!/bin/bash

set -euxo pipefail

if [[ "${target_platform}" == osx-* ]]; then
  export LDFLAGS="${LDFLAGS} -lz -framework CoreFoundation -Xlinker -undefined -Xlinker dynamic_lookup"
else
  export LDFLAGS="${LDFLAGS} -lrt"
fi

if [[ "${target_platform}" == linux-aarch64 ]]; then
  echo "TODO debug why using gen-bazel-toolchain leads to undeclared inclusion(s) of pybind11"
else
source gen-bazel-toolchain

cat >> .bazelrc <<EOF

build --copt=-isysroot${CONDA_BUILD_SYSROOT}
build --host_copt=-isysroot${CONDA_BUILD_SYSROOT}
build --linkopt=-isysroot${CONDA_BUILD_SYSROOT}
build --host_linkopt=-isysroot${CONDA_BUILD_SYSROOT}
build --crosstool_top=//bazel_toolchain:toolchain
build --logging=6
build --verbose_failures
build --toolchain_resolution_debug
build --define=PREFIX=${PREFIX}
build --define=PROTOBUF_INCLUDE_PATH=${PREFIX}/include
build --local_cpu_resources=${CPU_COUNT}"
EOF
fi

export LD_LIBRARY_PATH="${LD_LIBRARY_PATH+LD_LIBRARY_PATH:}:$PREFIX/lib"

CUSTOM_BAZEL_OPTIONS="--bazel_options=--logging=6 --bazel_options=--verbose_failures"

echo "Building...."
${PYTHON} build/build.py --use_clang=true --target_cpu_features default --enable_mkl_dnn ${CUSTOM_BAZEL_OPTIONS} --clang_path=${BUILD_PREFIX}/bin/clang
echo "Building done."

# Clean up to speedup postprocessing
echo "Issuing bazel clean..."
pushd build
bazel clean --expunge
popd

echo "Issuing bazel shutdown..."
bazel shutdown

echo "Installing jaxlib wheel..."
${PYTHON} -m pip install dist/jaxlib-*.whl --no-build-isolation --no-deps
