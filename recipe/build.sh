#!/bin/bash
set -euxo pipefail

export JAX_RELEASE=$PKG_VERSION

$RECIPE_DIR/add_py_toolchain.sh

if [[ "${host_platform}" == osx-* ]]; then
  export LDFLAGS="${LDFLAGS} -lz -framework CoreFoundation -Xlinker -undefined -Xlinker dynamic_lookup"
  # Remove stdlib=libc++; this is the default and errors on C sources.
  export CXXFLAGS="${CXXFLAGS/-stdlib=libc++} -D_LIBCPP_DISABLE_AVAILABILITY"
else
  export LDFLAGS="${LDFLAGS} -lrt"

  # See https://github.com/llvm/llvm-project/issues/85656
  # Otherwise, this will cause linkage errors with a GCC-built abseil
  export CXXFLAGS="${CXXFLAGS} -fclang-abi-compat=17"
fi
if [[ "${host_platform}" == "linux-64" || "${host_platform}" == "linux-aarch64" ]]; then
    # https://github.com/conda-forge/jaxlib-feedstock/issues/310
    # Explicitly force non-executable stack to fix compatibility with glibc 2.41, due to:
    # xla_extension.so: cannot enable executable stack as shared object requires: Invalid argument
    LDFLAGS+=" -Wl,-z,noexecstack"
fi
export CFLAGS="${CFLAGS} -DNDEBUG -Dabsl_nullable= -Dabsl_nonnull="
export CXXFLAGS="${CXXFLAGS} -DNDEBUG -Dabsl_nullable= -Dabsl_nonnull="

if [[ "${cuda_compiler_version:-None}" != "None" ]]; then
    if [[ ${cuda_compiler_version} == 12* ]]; then
        export HERMETIC_CUDA_COMPUTE_CAPABILITIES=sm_60,sm_70,sm_75,sm_80,sm_86,sm_89,sm_90,sm_100,sm_120,compute_120
    else
        export HERMETIC_CUDA_COMPUTE_CAPABILITIES=sm_75,sm_80,sm_86,sm_89,sm_90,sm_100,sm_110,sm_120,compute_120
    fi
    if [[ "${host_platform}" == "linux-64" ]]; then
        export CUDA_ARCH="x86_64-linux"
    elif [[ "${host_platform}" == "linux-aarch64" ]]; then
	export CUDA_ARCH="sbsa-linux"
    else
	echo "Unknown architecture for CUDA"
	exit 1
    fi
    export CUDA_HOME="${BUILD_PREFIX}/targets/${CUDA_ARCH}"
    export TF_CUDA_PATHS="${BUILD_PREFIX}/targets/${CUDA_ARCH},${PREFIX}/targets/${CUDA_ARCH}"
    # Needed for some nvcc binaries
    export PATH=$PATH:${BUILD_PREFIX}/nvvm/bin
    # XLA can only cope with a single cuda header include directory, merge both
    rsync -a ${PREFIX}/targets/${CUDA_ARCH}/include/ ${BUILD_PREFIX}/targets/${CUDA_ARCH}/include/

    # Although XLA supports a non-hermetic build, it still tries to find headers in the hermetic locations.
    # We do this in the BUILD_PREFIX to not have any impact on the resulting jaxlib package.
    # Otherwise, these copied files would be included in the package.
    rm -rf ${BUILD_PREFIX}/targets/${CUDA_ARCH}/include/third_party
    mkdir -p ${BUILD_PREFIX}/targets/${CUDA_ARCH}/include/third_party/gpus/cuda/extras/CUPTI
    cp -r ${PREFIX}/targets/${CUDA_ARCH}/include ${BUILD_PREFIX}/targets/${CUDA_ARCH}/include/third_party/gpus/cuda/
    cp -r ${PREFIX}/targets/${CUDA_ARCH}/include ${BUILD_PREFIX}/targets/${CUDA_ARCH}/include/third_party/gpus/cuda/extras/CUPTI/
    mkdir -p ${BUILD_PREFIX}/targets/${CUDA_ARCH}/include/third_party/gpus/cudnn
    cp ${PREFIX}/include/cudnn*.h ${BUILD_PREFIX}/targets/${CUDA_ARCH}/include/third_party/gpus/cudnn/
    mkdir -p ${BUILD_PREFIX}/targets/${CUDA_ARCH}/include/third_party/nccl
    cp ${PREFIX}/include/nccl*.h ${BUILD_PREFIX}/targets/${CUDA_ARCH}/include/third_party/nccl/
    # Work around clang CUDA host compilation colliding with libstdc++'s
    # __attribute__((__noinline__)) usage via host_defines.h macro expansion.
    # Patch both build and host CUDA include trees used by this build.
    for CUDA_INCLUDE_ROOT in "${BUILD_PREFIX}/targets/${CUDA_ARCH}/include" "${PREFIX}/targets/${CUDA_ARCH}/include"; do
      while IFS= read -r CUDA_HOST_DEFINES; do
        sed -i 's/#if defined(__CUDACC__) || defined(__CUDA_ARCH__) || defined(__CUDA_LIBDEVICE__)/#if (defined(__CUDACC__) || defined(__CUDA_ARCH__) || defined(__CUDA_LIBDEVICE__)) \&\& !defined(__clang__)/' "${CUDA_HOST_DEFINES}"
        sed -i 's/#if (defined(__CUDACC__) \&\& !defined(__clang__)) || defined(__CUDA_ARCH__) || defined(__CUDA_LIBDEVICE__)/#if (defined(__CUDACC__) || defined(__CUDA_ARCH__) || defined(__CUDA_LIBDEVICE__)) \&\& !defined(__clang__)/' "${CUDA_HOST_DEFINES}"
      done < <(find "${CUDA_INCLUDE_ROOT}" -path '*/crt/host_defines.h' -print)

      # Work around clang + CUDA 12 CUB placement-new resolution in device code.
      while IFS= read -r CUDA_CUB_BLOCK_LOAD; do
        sed -i 's|new (\&dst_items\[i\]) T(block_src_it\[warp_offset + tid + (i \* CUB_PTX_WARP_THREADS)\]);|detail::uninitialized_copy_single(\&dst_items[i], block_src_it[warp_offset + tid + (i * CUB_PTX_WARP_THREADS)]);|' "${CUDA_CUB_BLOCK_LOAD}"
        sed -i 's|new (\&dst_items\[i\]) T(block_src_it\[src_pos\]);|detail::uninitialized_copy_single(\&dst_items[i], block_src_it[src_pos]);|' "${CUDA_CUB_BLOCK_LOAD}"
      done < <(find "${CUDA_INCLUDE_ROOT}" -path '*/cub/block/block_load.cuh' -print)
    done
    export LOCAL_CUDA_PATH="${BUILD_PREFIX}/targets/${CUDA_ARCH}"
    export LOCAL_CUDNN_PATH="${PREFIX}/targets/${CUDA_ARCH}"
    export LOCAL_NCCL_PATH="${PREFIX}/targets/${CUDA_ARCH}"
    mkdir -p ${BUILD_PREFIX}/targets/${CUDA_ARCH}/bin
    test -f ${BUILD_PREFIX}/targets/${CUDA_ARCH}/bin/ptxas || ln -s $(which ptxas) ${BUILD_PREFIX}/targets/${CUDA_ARCH}/bin/ptxas
    test -f ${BUILD_PREFIX}/targets/${CUDA_ARCH}/bin/nvlink || ln -s $(which nvlink) ${BUILD_PREFIX}/targets/${CUDA_ARCH}/bin/nvlink
    test -f ${BUILD_PREFIX}/targets/${CUDA_ARCH}/bin/fatbinary || ln -s $(which fatbinary) ${BUILD_PREFIX}/targets/${CUDA_ARCH}/bin/fatbinary

    # rules_ml_toolchain expects an nvml redist directory for local CUDA builds.
    # Conda packages only provide the NVML stub library, so expose the target root
    # under the expected name to satisfy the repository rule on clean builds.
    if [[ ! -e "${LOCAL_CUDA_PATH}/nvml" ]]; then
      ln -s . "${LOCAL_CUDA_PATH}/nvml"
    fi
    export TF_CUDA_VERSION="${cuda_compiler_version}"
    export TF_CUDNN_VERSION=$(conda list -p $PREFIX ^cudnn$ | awk '$1 == "cudnn" {split($2, a, "."); print a[1]"."a[2]"."a[3]}')
    if [[ "${host_platform}" == "linux-aarch64" ]]; then
        export TF_CUDA_PATHS="${CUDA_HOME}/targets/sbsa-linux,${TF_CUDA_PATHS}"
    fi
    export TF_NEED_CUDA=1
    export TF_NCCL_VERSION=$(pkg-config nccl --modversion | grep -Po '\d+\.\d+')
    export CUDA_COMPILER_MAJOR_VERSION=$(echo "$cuda_compiler_version" | cut -d '.' -f 1)
    CUDA_ARGS="--wheels=jaxlib,jax-cuda-plugin,jax-cuda-pjrt \
               --cuda_compute_capabilities=$HERMETIC_CUDA_COMPUTE_CAPABILITIES \
               --cuda_major_version=${CUDA_COMPILER_MAJOR_VERSION} \
               --cuda_version=$TF_CUDA_VERSION \
               --cudnn_version=$TF_CUDNN_VERSION \
               --build_cuda_with_clang"
fi

if [[ "${CI:-}" == "github_actions" ]]; then
  export CPU_COUNT=2
fi

source gen-bazel-toolchain

cat >> .bazelrc <<EOF

build --crosstool_top=//bazel_toolchain:toolchain
build --platforms=//bazel_toolchain:target_platform
build --host_platform=//bazel_toolchain:build_platform
build --extra_toolchains=//bazel_toolchain:cc_cf_toolchain
build --extra_toolchains=//bazel_toolchain:cc_cf_host_toolchain
build --verbose_failures
build --define=BUILD_PREFIX=${BUILD_PREFIX}
build --define=PREFIX=${PREFIX}
build --define=PROTOBUF_INCLUDE_PATH=${PREFIX}/include
build --local_resources=cpu=${CPU_COUNT}
build --define=with_cross_compiler_support=true
build --repo_env=GRPC_BAZEL_DIR=${PREFIX}/share/bazel/grpc/bazel
build --repo_env=PROTOBUF_BAZEL_DIR=${PREFIX}/share/bazel/protobuf/bazel

# Tell nvcc builds to use conda's NVCC
build:build_cuda_with_nvcc --action_env=CONDA_USE_NVCC=1
EOF

# clang's __clang_cuda_runtime_wrapper.h unconditionally includes
# texture_indirect_functions.h, which was removed in CUDA 13.0
if [[ ${cuda_compiler_version:-None} != "None" && ${cuda_compiler_version} != 12* ]]; then
    for hdr in texture_indirect_functions.h; do
        test -f "${BUILD_PREFIX}/targets/${CUDA_ARCH}/include/${hdr}" \
            || touch "${BUILD_PREFIX}/targets/${CUDA_ARCH}/include/${hdr}"
    done
fi

if [[ "${host_platform}" == "osx-arm64" || "${host_platform}" != "${build_platform}" ]]; then
  echo "build --cpu=${TARGET_CPU}" >> .bazelrc
fi

# For debugging
# CUSTOM_BAZEL_OPTIONS="${CUSTOM_BAZEL_OPTIONS} --bazel_options=--subcommands"

# Force static linkage with protobuf to avoid definition collisions,
# see https://github.com/conda-forge/jaxlib-feedstock/issues/89
# We have modified the system lib here to link to libprotobuf.a
export TF_SYSTEM_LIBS="boringssl,com_github_googlecloudplatform_google_cloud_cpp,com_github_grpc_grpc,flatbuffers,zlib,com_google_absl,com_googlesource_code_re2,com_google_protobuf"

if [[ "${host_platform}" != "osx-arm64" ]]; then
    export TF_SYSTEM_LIBS="${TF_SYSTEM_LIBS},onednn"
fi

# Mark as a release build
EXTRA="--bazel_options=--repo_env=ML_WHEEL_TYPE=release ${CUDA_ARGS:-}"

if [[ "${host_platform}" == "osx-arm64" || "${host_platform}" != "${build_platform}" ]]; then
    EXTRA="${EXTRA} --target_cpu ${TARGET_CPU}"
fi

# Never use the Appe toolchain
sed -i '/local_config_apple/d' .bazelrc
if [[ "${host_platform}" == linux-* ]]; then
    EXTRA="${EXTRA} --clang_path $(command -v ${CC})"

    # Remove incompatible argument from bazelrc
    sed -i '/Qunused-arguments/d' .bazelrc
    if [[ ${cuda_compiler_version:-None} != "None" ]]; then
        # Clang handles device code; use recipe's toolchain instead of local_config_cuda
        sed -i '/TF_NVCC_CLANG/d' .bazelrc
        sed -i -E '/--crosstool_top="?@local_config_cuda\/\/crosstool:toolchain"?/d' .bazelrc
        sed -i -E '/--host_crosstool_top="?@local_config_cuda\/\/crosstool:toolchain"?/d' .bazelrc
    fi
fi

${PYTHON} build/build.py build \
    --target_cpu_features default \
    ${EXTRA}

# Clean up to speedup postprocessing
pushd build
bazel clean --expunge
popd

pushd $SP_DIR
${PYTHON} -m pip install $SRC_DIR/dist/jaxlib-*.whl

# Add INSTALLER file and remove RECORD, workaround for
# https://github.com/conda-forge/jaxlib-feedstock/issues/293
JAXLIB_DIST_INFO_DIR="${SP_DIR}/jaxlib-${PKG_VERSION}.dist-info"
echo "conda" > "${JAXLIB_DIST_INFO_DIR}/INSTALLER"
rm -f "${JAXLIB_DIST_INFO_DIR}/RECORD"

# Avoid printing all symbols
set +x

if [[ "${cuda_compiler_version:-None}" != "None" ]]; then
  ${PYTHON} -m pip install $SRC_DIR/dist/jax_cuda*_plugin*.whl
  ${PYTHON} -m pip install $SRC_DIR/dist/jax_cuda*_pjrt*.whl

  # Add INSTALLER file and remove RECORD, workaround for
  # https://github.com/conda-forge/jaxlib-feedstock/issues/293
  JAX_CUDA_PJRT_DIST_INFO_DIR="${SP_DIR}/jax_cuda${CUDA_COMPILER_MAJOR_VERSION}_pjrt-${PKG_VERSION}.dist-info"
  echo "conda" > "${JAX_CUDA_PJRT_DIST_INFO_DIR}/INSTALLER"
  rm -f "${JAX_CUDA_PJRT_DIST_INFO_DIR}/RECORD"
  JAX_CUDA_PLUGIN_DIST_INFO_DIR="${SP_DIR}/jax_cuda${CUDA_COMPILER_MAJOR_VERSION}_plugin-${PKG_VERSION}.dist-info"
  echo "conda" > "${JAX_CUDA_PLUGIN_DIST_INFO_DIR}/INSTALLER"
  rm -f "${JAX_CUDA_PLUGIN_DIST_INFO_DIR}/RECORD"

  # Regression test for https://github.com/conda-forge/jaxlib-feedstock/issues/320
  if [[ "${host_platform}" == linux-* ]]; then
    # Scan all .so files in both plugin directories and error if any FLAGS_* symbols are present.
    declare -a PLUGIN_DIRS=(
      "${SP_DIR}/jax_plugins/xla_cuda${CUDA_COMPILER_MAJOR_VERSION}"
      "${SP_DIR}/jax_cuda${CUDA_COMPILER_MAJOR_VERSION}_plugin"
    )
    echo "Scanning CUDA plugin directories for .so files and FLAGS_* symbols:"
    for DIR in "${PLUGIN_DIRS[@]}"; do
      if [[ -d "${DIR}" ]]; then
        echo " - ${DIR}"
        mapfile -t SO_FILES < <(find "${DIR}" -type f -name '*.so' -print | sort)
        if (( ${#SO_FILES[@]} == 0 )); then
          echo "   (no .so files found)"
          continue
        fi
        echo "   .so files:"
        for SO in "${SO_FILES[@]}"; do
          echo "     * ${SO}"
        done
        # Prefer nm -s as requested; fall back to plain nm if -s is unsupported to avoid hard failure.
        # Fail the build if any symbol starting with FLAGS_ is present.
        for SO in "${SO_FILES[@]}"; do
          SYMBOLS_OUTPUT=$(nm -s "${SO}" 2>/dev/null || nm "${SO}")
          if echo "${SYMBOLS_OUTPUT}" | grep -E '(^|[^A-Za-z0-9_])FLAGS_[A-Za-z0-9_]+' >/dev/null; then
            echo "Error: Unexpected FLAGS_* symbols found in ${SO}:" >&2
            echo "----------------------------------------" >&2
            echo "${SYMBOLS_OUTPUT}" | grep -E '(^|[^A-Za-z0-9_])FLAGS_[A-Za-z0-9_]+' >&2 || true
            echo "----------------------------------------" >&2
            exit 1
          fi
        done
      else
        echo "Warning: ${DIR} not found; skipping" >&2
      fi
    done
    echo "No FLAGS_* symbols found in the CUDA plugin directory, the test was successul"
  fi
fi

popd
