#!/bin/bash

set -euxo pipefail

export JAX_RELEASE=$PKG_VERSION

if [[ "${target_platform}" == osx-* ]]; then
  export LDFLAGS="${LDFLAGS} -lz -framework CoreFoundation -Xlinker -undefined -Xlinker dynamic_lookup"
  # Remove stdlib=libc++; this is the default and errors on C sources.
  export CXXFLAGS=${CXXFLAGS/-stdlib=libc++}
else
  export LDFLAGS="${LDFLAGS} -lrt"
fi
export CFLAGS="${CFLAGS} -DNDEBUG"
export CXXFLAGS="${CXXFLAGS} -DNDEBUG"

if [[ "${cuda_compiler_version:-None}" != "None" ]]; then
    if [[ ${cuda_compiler_version} == 11.8 ]]; then
        export TF_CUDA_COMPUTE_CAPABILITIES=sm_35,sm_50,sm_60,sm_62,sm_70,sm_72,sm_75,sm_80,sm_86,sm_87,sm_89,sm_90,compute_90
	export TF_CUDA_PATHS="${CUDA_HOME},${PREFIX}"
    elif [[ ${cuda_compiler_version} == 12* ]]; then
        export TF_CUDA_COMPUTE_CAPABILITIES=sm_60,sm_70,sm_75,sm_80,sm_86,sm_89,sm_90,compute_90
        export CUDA_HOME="${BUILD_PREFIX}/targets/x86_64-linux"
        export TF_CUDA_PATHS="${BUILD_PREFIX}/targets/x86_64-linux,${PREFIX}/targets/x86_64-linux"
	# Needed for some nvcc binaries
	export PATH=$PATH:${BUILD_PREFIX}/nvvm/bin
	# XLA can only cope with a single cuda header include directory, merge both
	rsync -a ${PREFIX}/targets/x86_64-linux/include/ ${BUILD_PREFIX}/targets/x86_64-linux/include/
    else
        echo "unsupported cuda version."
        exit 1
    fi

    export TF_CUDA_VERSION="${cuda_compiler_version}"
    export TF_CUDNN_VERSION="${cudnn}"
    if [[ "${target_platform}" == "linux-aarch64" ]]; then
        export TF_CUDA_PATHS="${CUDA_HOME}/targets/sbsa-linux,${TF_CUDA_PATHS}"
    fi
    export TF_NEED_CUDA=1
    export TF_NCCL_VERSION=$(pkg-config nccl --modversion | grep -Po '\d+\.\d+')

    CUDA_ARGS="--enable_cuda \
               --enable_nccl \
               --cudnn_path=${PREFIX}   \
               --cuda_compute_capabilities=$TF_CUDA_COMPUTE_CAPABILITIES \
               --cuda_version=$TF_CUDA_VERSION \
               --cudnn_version=$TF_CUDNN_VERSION"
fi

if [[ "${CI:-}" == "github_actions" ]]; then
  export CPU_COUNT=2
fi

source gen-bazel-toolchain

cat >> .bazelrc <<EOF
build --crosstool_top=//bazel_toolchain:toolchain
build --logging=6
build --verbose_failures
build --toolchain_resolution_debug
build --define=PREFIX=${PREFIX}
build --define=PROTOBUF_INCLUDE_PATH=${PREFIX}/include
build --local_cpu_resources=${CPU_COUNT}
build --define=with_cross_compiler_support=true
EOF

if [[ "${target_platform}" == "osx-arm64" || "${target_platform}" != "${build_platform}" ]]; then
  echo "build --cpu=${TARGET_CPU}" >> .bazelrc
fi

# For debugging
# CUSTOM_BAZEL_OPTIONS="${CUSTOM_BAZEL_OPTIONS} --bazel_options=--subcommands"

if [[ "${target_platform}" == "osx-64" ]]; then
  # Tensorflow doesn't cope yet with an explicit architecture (darwin_x86_64) on osx-64 yet.
  TARGET_CPU=darwin
fi

# Force static linkage with protobuf to avoid definition collisions,
# see https://github.com/conda-forge/jaxlib-feedstock/issues/89
#
# Thus: don't add com_google_protobuf here.
export TF_SYSTEM_LIBS="boringssl,com_github_googlecloudplatform_google_cloud_cpp,com_github_grpc_grpc,flatbuffers,zlib,com_google_absl"

if [[ "${target_platform}" == "osx-arm64" || "${target_platform}" != "${build_platform}" ]]; then
    EXTRA="--target_cpu ${TARGET_CPU}"
else
    EXTRA="${CUDA_ARGS:-}"
fi
if [[ "${target_platform}" == linux-* ]]; then
    EXTRA="${EXTRA} --nouse_clang"
fi
${PYTHON} build/build.py \
    --target_cpu_features default \
    --enable_mkl_dnn \
    ${EXTRA}

# Clean up to speedup postprocessing
pushd build
bazel clean
popd

pushd $SP_DIR
# pip doesn't want to install cleanly in all cases, so we use the fact that we can unzip it.
unzip $SRC_DIR/dist/jaxlib-*.whl
popd
