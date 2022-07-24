#!/bin/bash

set -euxo pipefail

export PATH="$PWD:$PATH"
export CC=$(basename $CC)
export CXX=$(basename $CXX)
export LIBDIR=$PREFIX/lib
export INCLUDEDIR=$PREFIX/include

mkdir -p ./bazel_output_base
export CUSTOM_BAZEL_OPTIONS=""
# Set this to something as otherwise, it would include CFLAGS which itself contains a host path and this then breaks bazel's include path validation.
export CC_OPT_FLAGS="-O2"

if [[ "${target_platform}" == osx-* ]]; then
  export LDFLAGS="${LDFLAGS} -lz -framework CoreFoundation -Xlinker -undefined -Xlinker dynamic_lookup"
else
  export LDFLAGS="${LDFLAGS} -lrt"
fi
sed -i -e 's/c++14/c++17/g' .bazelrc
export CFLAGS="${CFLAGS} -DNDEBUG"
export CXXFLAGS="${CXXFLAGS} -DNDEBUG"
source gen-bazel-toolchain

CUSTOM_BAZEL_OPTIONS="--bazel_options=--crosstool_top=//bazel_toolchain:toolchain --bazel_options=--logging=6 --bazel_options=--verbose_failures --bazel_options=--toolchain_resolution_debug --bazel_options=--define=PREFIX=${PREFIX} --bazel_options=--define=PROTOBUF_INCLUDE_PATH=${PREFIX}/include
--bazel_options=--local_cpu_resources=${CPU_COUNT}"
# For debugging
# CUSTOM_BAZEL_OPTIONS="${CUSTOM_BAZEL_OPTIONS} --bazel_options=--subcommands"

if [[ "${target_platform}" == "osx-64" ]]; then
  # Tensorflow doesn't cope yet with an explicit architecture (darwin_x86_64) on osx-64 yet.
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
    
    export GCC_HOST_COMPILER_PATH="${GCC}"
    export GCC_HOST_COMPILER_PREFIX="$(dirname ${GCC})"

    export TF_CUDA_PATHS="${PREFIX},${CUDA_HOME}"
    export TF_NEED_CUDA=1
    export TF_CUDA_VERSION="${cuda_compiler_version}"
    export TF_CUDNN_VERSION="${cudnn}"
    export TF_NCCL_VERSION=$(pkg-config nccl --modversion | grep -Po '\d+\.\d+')

    export LDFLAGS="${LDFLAGS//-Wl,-z,now/-Wl,-z,lazy}"
    export CC_OPT_FLAGS="-march=nocona -mtune=haswell"

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
if [[ "${cuda_compiler_version:-None}" != "None" ]]; then
  export TF_SYSTEM_LIBS="boringssl,com_github_googlecloudplatform_google_cloud_cpp,flatbuffers"
else
  export TF_SYSTEM_LIBS="boringssl,com_google_absl,com_github_googlecloudplatform_google_cloud_cpp,com_github_grpc_grpc,flatbuffers,zlib"
fi

bazel clean --expunge
bazel shutdown

if [[ "${target_platform}" == "osx-arm64" ]]; then
  ${PYTHON} build/build.py --target_cpu_features default --enable_mkl_dnn ${CUSTOM_BAZEL_OPTIONS} --target_cpu ${TARGET_CPU}
else
  ${PYTHON} build/build.py --target_cpu_features default --enable_mkl_dnn ${CUSTOM_BAZEL_OPTIONS} --bazel_options=--cpu --bazel_options=${TARGET_CPU} ${CUDA_ARGS:-}
fi

# Clean up to speedup postprocessing
pushd build
bazel clean
popd

pushd $SP_DIR
# pip doesn't want to install cleanly in all cases, so we use the fact that we can unzip it.
unzip $SRC_DIR/dist/jaxlib-*.whl
popd
