#!/bin/bash

set -euxo pipefail

export PATH="$PWD:$PATH"
export CC=$(basename $CC)
export CXX=$(basename $CXX)
export LIBDIR=$PREFIX/lib
export INCLUDEDIR=$PREFIX/include

export TF_IGNORE_MAX_BAZEL_VERSION="1"


if [[ "${target_platform}" == osx-* ]]; then
  export LDFLAGS="${LDFLAGS} -lz -framework CoreFoundation -Xlinker -undefined -Xlinker dynamic_lookup"
else
  export LDFLAGS="${LDFLAGS} -lrt"
fi
sed -i -e 's/c++14/c++17/g' .bazelrc
export CFLAGS="${CFLAGS} -DNDEBUG"
export CXXFLAGS="${CXXFLAGS} -DNDEBUG"

if [[ "${cuda_compiler_version:-None}" != "None" ]]; then
   source ${RECIPE_DIR}/gen-bazel-toolchain.sh
else
   source gen-bazel-toolchain
fi

CUSTOM_BAZEL_OPTIONS="--bazel_options=--crosstool_top=//custom_toolchain:toolchain --bazel_options=--logging=6 --bazel_options=--verbose_failures --bazel_options=--toolchain_resolution_debug --bazel_options=--define=PREFIX=${PREFIX} --bazel_options=--define=PROTOBUF_INCLUDE_PATH=${PREFIX}/include"
# For debugging
# CUSTOM_BAZEL_OPTIONS="${CUSTOM_BAZEL_OPTIONS} --bazel_options=--subcommands"

if [[ "${target_platform}" == "osx-64" ]]; then
#   Tensorflow doesn't cope yet with an explicit architecture (darwin_x86_64) on osx-64 yet.
  TARGET_CPU=darwin
fi

if [[ "${cuda_compiler_version:-None}" != "None" ]]; then
   if [[ ${cuda_compiler_version} == 10.* ]]; then
       export TF_CUDA_COMPUTE_CAPABILITIES=sm_35,sm_50,sm_60,sm_62,sm_70,sm_72,sm_75,compute_75
   elif [[ ${cuda_compiler_version} == 11.0* ]]; then
       export TF_CUDA_COMPUTE_CAPABILITIES=sm_35,sm_50,sm_60,sm_62,sm_70,sm_72,sm_75,sm_80,compute_80
   elif [[ ${cuda_compiler_version} == 11.1 ]]; then
       export TF_CUDA_COMPUTE_CAPABILITIES=sm_35,sm_50,sm_60,sm_62,sm_70,sm_72,sm_75,sm_80,sm_86,compute_86
   elif [[ ${cuda_compiler_version} == 11.2 ]]; then
       export TF_CUDA_COMPUTE_CAPABILITIES=sm_35,sm_50,sm_60,sm_62,sm_70,sm_72,sm_75,sm_80,sm_86,compute_86
   else
       echo "unsupported cuda version."
       exit 1
   fi

   export TF_CUDA_VERSION="${cuda_compiler_version}"
   export TF_CUDNN_VERSION="${cudnn}"

   CUDA_ARGS="--enable_cuda \
              --enable_nccl \
              --cuda_path=$CUDA_HOME \
              --cudnn_path=$PREFIX   \
              --cuda_compute_capabilities=$TF_CUDA_COMPUTE_CAPABILITIES \
              --cuda_version=$TF_CUDA_VERSION \
              --cudnn_version=$TF_CUDNN_VERSION"
fi

# Force static linkage with protobuf to avoid definition collisions,
# see https://github.com/conda-forge/jaxlib-feedstock/issues/89
#
# Thus: don't add com_google_protobuf here.
# FIXME: Current global abseil pin is too old for jaxlib, readd com_google_absl once we are on a newer version.
if [[ "${cuda_compiler_version:-None}" != "None" ]]; then
    export BAZEL_LINKLIBS="-lstdc++"
    export TF_SYSTEM_LIBS="boringssl,com_github_googlecloudplatform_google_cloud_cpp,com_github_grpc_grpc,flatbuffers,zlib"
    export GCC_HOST_COMPILER_PATH="${GCC}"
    export GCC_HOST_COMPILER_PREFIX="$(dirname ${GCC})"
    export LDFLAGS="${LDFLAGS//-Wl,-z,now/-Wl,-z,lazy}"
else
    export TF_SYSTEM_LIBS="boringssl,com_github_googlecloudplatform_google_cloud_cpp,com_github_grpc_grpc,flatbuffers,zlib"
fi

if [[ "${target_platform}" == "osx-arm64" ]]; then
  ${PYTHON} build/build.py --target_cpu_features default --enable_mkl_dnn ${CUSTOM_BAZEL_OPTIONS} --target_cpu ${TARGET_CPU}
else
  ${PYTHON} build/build.py --target_cpu_features default --enable_mkl_dnn ${CUSTOM_BAZEL_OPTIONS} --bazel_options=--cpu --bazel_options=${TARGET_CPU} --bazel_options="--local_cpu_resources=${CPU_COUNT}" ${CUDA_ARGS:-}
fi

# Clean up to speedup postprocessing
pushd build
bazel clean
popd

pushd $SP_DIR
# pip doesn't want to install cleanly in all cases, so we use the fact that we can unzip it.
unzip $SRC_DIR/dist/jaxlib-*.whl
popd
