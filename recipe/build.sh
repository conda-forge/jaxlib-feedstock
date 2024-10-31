#!/bin/bash

set -euxo pipefail

if [[ "${target_platform}" == osx-* ]]; then
  export LDFLAGS="${LDFLAGS} -lz -framework CoreFoundation -Xlinker -undefined -Xlinker dynamic_lookup"
else
  export LDFLAGS="${LDFLAGS} -lrt"
fi

export LD_LIBRARY_PATH="${LD_LIBRARY_PATH+LD_LIBRARY_PATH:}:$PREFIX/lib"

# Build with clang on OSX-* and linux-aarch64. Stick with gcc on linux-64.
if [[ "${target_platform}" == linux-* ]]; then
  export BUILD_FLAGS="--use_clang=false"
else
  export BUILD_FLAGS="--use_clang=true --clang_path=${BUILD_PREFIX}/bin/clang"
fi


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
build --define=with_cuda=false
build --cxxopt=-I${PREFIX}/include
EOF

CUSTOM_BAZEL_OPTIONS="--bazel_options=--logging=6 --bazel_options=--verbose_failures"


# Unvendor from XLA using TF_SYSTEM_LIBS. You can find the list of supported libraries at:  
# https://github.com/openxla/xla/blob/main/third_party/tsl/third_party/systemlibs/syslibs_configure.bzl#L11
# TODO: RE2 fails with: external/xla/xla/hlo/parser/hlo_lexer.cc:244:8: error: no matching function for call to 'Consume'
  # if (!RE2::Consume(&consumable, *payload_pattern)) 
# Removed com_googlesource_code_re2
export TF_SYSTEM_LIBS="
  absl_py,
  astor_archive,
  astunparse_archive,
  boringssl,
  com_github_googlecloudplatform_google_cloud_cpp,
  com_github_grpc_grpc,
  com_google_absl,
  com_google_protobuf,
  curl,
  cython,
  dill_archive,
  double_conversion,
  flatbuffers,
  functools32_archive,
  gast_archive,
  gif,
  hwloc,
  icu,
  jsoncpp_git,
  libjpeg_turbo,
  nasm,
  nsync,
  org_sqlite,
  pasta,
  png,
  pybind11,
  six_archive,
  snappy,
  tblib_archive,
  termcolor_archive,
  typing_extensions_archive,
  wrapt,
  zlib"

bazel clean --expunge

echo "Building...."
${PYTHON} build/build.py ${BUILD_FLAGS} --target_cpu_features default --enable_mkl_dnn ${CUSTOM_BAZEL_OPTIONS}
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
