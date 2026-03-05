#!/bin/bash
set -euxo pipefail

export JAX_RELEASE=$PKG_VERSION

# Workaround a timestamp issue in rattler-build
# https://github.com/prefix-dev/rattler-build/issues/1865
touch -m -t 203510100101 $(find $BUILD_PREFIX/share/bazel/install -type f)

$RECIPE_DIR/add_py_toolchain.sh

if [[ "${target_platform}" == osx-* ]]; then
  export LDFLAGS="${LDFLAGS} -lz -framework CoreFoundation -Xlinker -undefined -Xlinker dynamic_lookup"
  # Remove stdlib=libc++; this is the default and errors on C sources.
  export CXXFLAGS="${CXXFLAGS/-stdlib=libc++} -D_LIBCPP_DISABLE_AVAILABILITY"
else
  export LDFLAGS="${LDFLAGS} -lrt"

  # See https://github.com/llvm/llvm-project/issues/85656
  # Otherwise, this will cause linkage errors with a GCC-built abseil
  export CXXFLAGS="${CXXFLAGS} -fclang-abi-compat=17"
fi
if [[ "${target_platform}" == "linux-64" || "${target_platform}" == "linux-aarch64" ]]; then
    # https://github.com/conda-forge/jaxlib-feedstock/issues/310
    # Explicitly force non-executable stack to fix compatibility with glibc 2.41, due to:
    # xla_extension.so: cannot enable executable stack as shared object requires: Invalid argument
    LDFLAGS+=" -Wl,-z,noexecstack"
fi
export CFLAGS="${CFLAGS} -DNDEBUG -Dabsl_nullable= -Dabsl_nonnull="
export CXXFLAGS="${CXXFLAGS} -DNDEBUG -Dabsl_nullable= -Dabsl_nonnull="

# Keep the source tree compatible with newer Abseil even if the static patch
# was not applied in the unpacked workdir for this build.
if [[ -f "jaxlib/weakref_lru_cache.cc" ]]; then
  perl -0pi -e 's/\bmu_\.lock\(\)/mu_.Lock()/g; s/\bmu_\.unlock\(\)/mu_.Unlock()/g' jaxlib/weakref_lru_cache.cc
fi
if [[ -d "jaxlib" ]]; then
  find jaxlib -type f \( -name '*.h' -o -name '*.cc' -o -name '*.cuh' \) \
    -exec perl -0pi -e 's/\babsl::(MutexLock|ReaderMutexLock|WriterMutexLock|ReleasableMutexLock)\s+([A-Za-z_][A-Za-z0-9_]*)\(\s*([A-Za-z_][A-Za-z0-9_]*(?:(?:->|\.)[A-Za-z_][A-Za-z0-9_]*)*)\s*([,\)])/absl::$1 $2\(&${3}$4/g' {} +
fi
if [[ -f "third_party/xla/xla/python/ifrt_proxy/common/test_utils.h" ]]; then
  perl -0pi -e 's/\babsl::MutexLock l\(mu_\);/absl::MutexLock l\(&mu_\);/g' third_party/xla/xla/python/ifrt_proxy/common/test_utils.h
fi
if [[ -f "third_party/xla/xla/tsl/lib/io/zlib_compression_options.h" ]]; then
  perl -0pi -e 's/\babsl::(MutexLock|ReaderMutexLock|WriterMutexLock|ReleasableMutexLock)\s+([A-Za-z_][A-Za-z0-9_]*)\((mu_|mutex_)\);/absl::$1 $2\(&${3}\);/g' third_party/xla/xla/tsl/lib/io/zlib_compression_options.h
fi
if [[ -d "third_party/xla" ]]; then
  find third_party/xla -type f \( -name '*.h' -o -name '*.cc' -o -name '*.cuh' \) \
    -exec perl -0pi -e 's/\babsl::(MutexLock|ReaderMutexLock|WriterMutexLock|ReleasableMutexLock)\s+([A-Za-z_][A-Za-z0-9_]*)\(\s*(mu_|mutex_|lock_)(\s*[,\)])/absl::$1 $2\(&${3}$4/g' {} +
fi

if [[ "${cuda_compiler_version:-None}" != "None" ]]; then
    if [[ ${cuda_compiler_version} == 12* ]]; then
        export HERMETIC_CUDA_COMPUTE_CAPABILITIES=sm_60,sm_70,sm_75,sm_80,sm_86,sm_89,sm_90,sm_100,sm_120,compute_120
    else
        export HERMETIC_CUDA_COMPUTE_CAPABILITIES=sm_75,sm_80,sm_86,sm_89,sm_90,sm_100,sm_110,sm_120,compute_120
    fi
    if [[ "${target_platform}" == "linux-64" ]]; then
        export CUDA_ARCH="x86_64-linux"
    elif [[ "${target_platform}" == "linux-aarch64" ]]; then
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
    export LOCAL_CUDA_PATH="${BUILD_PREFIX}/targets/${CUDA_ARCH}"
    export LOCAL_CUDNN_PATH="${PREFIX}/targets/${CUDA_ARCH}"
    export LOCAL_NCCL_PATH="${PREFIX}/targets/${CUDA_ARCH}"
    mkdir -p ${BUILD_PREFIX}/targets/${CUDA_ARCH}/bin
    test -f ${BUILD_PREFIX}/targets/${CUDA_ARCH}/bin/ptxas || ln -s $(which ptxas) ${BUILD_PREFIX}/targets/${CUDA_ARCH}/bin/ptxas
    test -f ${BUILD_PREFIX}/targets/${CUDA_ARCH}/bin/nvlink || ln -s $(which nvlink) ${BUILD_PREFIX}/targets/${CUDA_ARCH}/bin/nvlink
    test -f ${BUILD_PREFIX}/targets/${CUDA_ARCH}/bin/fatbinary || ln -s $(which fatbinary) ${BUILD_PREFIX}/targets/${CUDA_ARCH}/bin/fatbinary

    # CUDA's host_defines.h defines __noinline__ for __CUDACC__, which clashes
    # with libstdc++ headers under clang -x cuda.
    for CUDA_HOST_DEFINES in \
        "${PREFIX}/targets/${CUDA_ARCH}/include/crt/host_defines.h" \
        "${BUILD_PREFIX}/targets/${CUDA_ARCH}/include/crt/host_defines.h" \
        "${BUILD_PREFIX}/targets/${CUDA_ARCH}/include/third_party/gpus/cuda/include/crt/host_defines.h"; do
      if [[ -f "${CUDA_HOST_DEFINES}" ]] && ! grep -q "XLA_CUDA_NOINLINE_FIX" "${CUDA_HOST_DEFINES}"; then
        sed -i 's@#if defined(__CUDACC__) || defined(__CUDA_ARCH__) || defined(__CUDA_LIBDEVICE__)@#if (defined(__CUDACC__) || defined(__CUDA_ARCH__) || defined(__CUDA_LIBDEVICE__)) \&\& !defined(__clang__) /* XLA_CUDA_NOINLINE_FIX */@' "${CUDA_HOST_DEFINES}"
      fi
    done

    # CUB uses placement-new in block_load.cuh but CUDA 12.9 headers may not
    # pull in <new> transitively for clang CUDA builds.
    for CUB_BLOCK_LOAD in \
        "${PREFIX}/targets/${CUDA_ARCH}/include/cub/block/block_load.cuh" \
        "${BUILD_PREFIX}/targets/${CUDA_ARCH}/include/cub/block/block_load.cuh" \
        "${BUILD_PREFIX}/targets/${CUDA_ARCH}/include/third_party/gpus/cuda/include/cub/block/block_load.cuh"; do
      if [[ -f "${CUB_BLOCK_LOAD}" ]] && ! grep -q "XLA_CUDA_PLACEMENT_NEW_FIX" "${CUB_BLOCK_LOAD}"; then
        sed -i '/#include <cub\/config.cuh>/a #include <new>  // XLA_CUDA_PLACEMENT_NEW_FIX' "${CUB_BLOCK_LOAD}"
      fi
      if [[ -f "${CUB_BLOCK_LOAD}" ]]; then
        # clang CUDA fails to resolve placement new in these CUB paths with this toolchain.
        sed -i 's@new (&dst_items\[i\]) T(@dst_items[i] = T(@g' "${CUB_BLOCK_LOAD}"
      fi
    done

    export TF_CUDA_VERSION="${cuda_compiler_version}"
    export TF_CUDNN_VERSION="${cudnn}"
    if [[ "${target_platform}" == "linux-aarch64" ]]; then
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

# Newer toolchains can expose multiple GCC header versions (e.g. 13.x and 15.x),
# which makes the upstream script emit a multiline value that breaks sed.
GEN_BAZEL_TOOLCHAIN="$(command -v gen-bazel-toolchain || true)"
if [[ -z "${GEN_BAZEL_TOOLCHAIN}" ]]; then
  echo "Unable to find gen-bazel-toolchain in PATH"
  exit 1
fi
cp "${GEN_BAZEL_TOOLCHAIN}" ./gen-bazel-toolchain.local
awk '
  BEGIN { skip = "" }
  skip == "" && $0 ~ /^[[:space:]]*export GCC_HEADER_VERSION="\$\(/ {
    print "    export GCC_HEADER_VERSION=\"$(for d in ${BUILD_PREFIX}/lib/gcc/${CONDA_TOOLCHAIN_HOST}/*; do if [ -d \\\"${d}/include/c++\\\" ]; then basename \\\"${d}\\\"; fi; done | sort -V | tail -n1)\""
    skip = "gcc"
    next
  }
  skip == "gcc" {
    if ($0 ~ /^[[:space:]]*[)]"$/) {
      skip = ""
    }
    next
  }
  skip == "" && $0 ~ /^[[:space:]]*export BUILD_GCC_HEADER_VERSION="\$\(/ {
    print "    export BUILD_GCC_HEADER_VERSION=\"$(for d in ${BUILD_PREFIX}/lib/gcc/${CONDA_TOOLCHAIN_BUILD}/*; do if [ -d \\\"${d}/include/c++\\\" ]; then basename \\\"${d}\\\"; fi; done | sort -V | tail -n1)\""
    skip = "build"
    next
  }
  skip == "build" {
    if ($0 ~ /^[[:space:]]*[)]"$/) {
      skip = ""
    }
    next
  }
  { print }
' ./gen-bazel-toolchain.local > ./gen-bazel-toolchain.local.tmp
mv ./gen-bazel-toolchain.local.tmp ./gen-bazel-toolchain.local
source ./gen-bazel-toolchain.local

# Make build-prefix headers visible to Bazel's include scanner as toolchain builtins.
for CFG in bazel_toolchain/cc_toolchain_config.bzl bazel_toolchain/cc_toolchain_build_config.bzl; do
  sed -i "/cxx_builtin_include_directories = \\[/a\\            \"${BUILD_PREFIX}/include\"," "${CFG}"
done

# The generated Bazel toolchain uses relative tool names (e.g. x86_64-conda-linux-gnu-clang).
# Ensure those names exist in bazel_toolchain/ by symlinking to real binaries.
if [[ "${target_platform}" == linux-* ]]; then
  for TOOL in "${CC}" "${LD}" "${NM}" "${STRIP}"; do
    TOOL_BIN="$(command -v "${TOOL}" || true)"
    if [[ -n "${TOOL_BIN}" ]]; then
      ln -sf "${TOOL_BIN}" "bazel_toolchain/$(basename "${TOOL}")"
    fi
  done

  # clang-20 used by some Bazel tool builds does not discover libstdc++ headers.
  # Register GCC C++ headers as toolchain built-ins.
  GCC_CXX_HEADER_VERSION="$(
    for d in "${BUILD_PREFIX}/lib/gcc/${CONDA_TOOLCHAIN_HOST}"/*; do
      if [[ -d "${d}/include/c++" ]]; then
        basename "${d}"
      fi
    done | sort -V | tail -n1
  )"
  if [[ -n "${GCC_CXX_HEADER_VERSION}" ]]; then
    GCC_CXX_INCLUDE_BASE="${BUILD_PREFIX}/lib/gcc/${CONDA_TOOLCHAIN_HOST}/${GCC_CXX_HEADER_VERSION}/include/c++"
    GCC_CXX_INCLUDE_TARGET="${GCC_CXX_INCLUDE_BASE}/${CONDA_TOOLCHAIN_HOST}"
    GCC_CXX_INCLUDE_BACKWARD="${GCC_CXX_INCLUDE_BASE}/backward"
    for CFG in bazel_toolchain/cc_toolchain_config.bzl bazel_toolchain/cc_toolchain_build_config.bzl; do
      sed -i "/cxx_builtin_include_directories = \\[/a\\            \"${GCC_CXX_INCLUDE_BACKWARD}\"," "${CFG}"
      sed -i "/cxx_builtin_include_directories = \\[/a\\            \"${GCC_CXX_INCLUDE_TARGET}\"," "${CFG}"
      sed -i "/cxx_builtin_include_directories = \\[/a\\            \"${GCC_CXX_INCLUDE_BASE}\"," "${CFG}"
    done
    export CPLUS_INCLUDE_PATH="${PREFIX}/include:${BUILD_PREFIX}/include:${GCC_CXX_INCLUDE_BASE}:${GCC_CXX_INCLUDE_TARGET}:${GCC_CXX_INCLUDE_BACKWARD}${CPLUS_INCLUDE_PATH:+:${CPLUS_INCLUDE_PATH}}"
  fi
  export LIBRARY_PATH="${PREFIX}/lib:${BUILD_PREFIX}/lib${LIBRARY_PATH:+:${LIBRARY_PATH}}"

fi

# Add small source-compatible aliases directly in the build env headers.
for ABSL_MUTEX_HEADER in \
  "${PREFIX}/include/absl/synchronization/mutex.h" \
  "${BUILD_PREFIX}/include/absl/synchronization/mutex.h"; do
  if [[ -f "${ABSL_MUTEX_HEADER}" ]] && ! grep -q "XLA_ABSL_MUTEX_COMPAT" "${ABSL_MUTEX_HEADER}"; then
    perl -0pi -e 's|void Unlock\(\) ABSL_UNLOCK_FUNCTION\(\);\n|void Unlock() ABSL_UNLOCK_FUNCTION();\n\n  // XLA_ABSL_MUTEX_COMPAT\n  void lock() ABSL_EXCLUSIVE_LOCK_FUNCTION() { Lock(); }\n  void unlock() ABSL_UNLOCK_FUNCTION() { Unlock(); }\n  [[nodiscard]] bool try_lock() ABSL_EXCLUSIVE_TRYLOCK_FUNCTION(true) { return TryLock(); }\n  void lock_shared() ABSL_SHARED_LOCK_FUNCTION() { ReaderLock(); }\n  void unlock_shared() ABSL_UNLOCK_FUNCTION() { ReaderUnlock(); }\n  [[nodiscard]] bool try_lock_shared() ABSL_SHARED_TRYLOCK_FUNCTION(true) { return ReaderTryLock(); }\n|s' "${ABSL_MUTEX_HEADER}"
    perl -0pi -e 's|explicit MutexLock\(Mutex\* absl_nonnull mu\) ABSL_EXCLUSIVE_LOCK_FUNCTION\(mu\)\n      : mu_\(mu\) \{\n    this->mu_->Lock\(\);\n  \}\n|explicit MutexLock(Mutex* absl_nonnull mu) ABSL_EXCLUSIVE_LOCK_FUNCTION(mu)\n      : mu_(mu) {\n    this->mu_->Lock();\n  }\n\n  // XLA_ABSL_MUTEX_COMPAT\n  explicit MutexLock(Mutex& mu) : MutexLock(&mu) {}\n|s' "${ABSL_MUTEX_HEADER}"
    perl -0pi -e 's|explicit MutexLock\(Mutex& mu\) : MutexLock\(&mu\) \{\}\n|explicit MutexLock(Mutex& mu) : MutexLock(&mu) {}\n  explicit MutexLock(Mutex& mu, const Condition& cond) : MutexLock(&mu, cond) {}\n|s' "${ABSL_MUTEX_HEADER}"
    perl -0pi -e 's|explicit ReaderMutexLock\(Mutex\* absl_nonnull mu\) ABSL_SHARED_LOCK_FUNCTION\(mu\)\n      : mu_\(mu\) \{\n    mu->ReaderLock\(\);\n  \}\n|explicit ReaderMutexLock(Mutex* absl_nonnull mu) ABSL_SHARED_LOCK_FUNCTION(mu)\n      : mu_(mu) {\n    mu->ReaderLock();\n  }\n\n  // XLA_ABSL_MUTEX_COMPAT\n  explicit ReaderMutexLock(Mutex& mu) : ReaderMutexLock(&mu) {}\n|s' "${ABSL_MUTEX_HEADER}"
    perl -0pi -e 's|explicit ReaderMutexLock\(Mutex& mu\) : ReaderMutexLock\(&mu\) \{\}\n|explicit ReaderMutexLock(Mutex& mu) : ReaderMutexLock(&mu) {}\n  explicit ReaderMutexLock(Mutex& mu, const Condition& cond) : ReaderMutexLock(&mu, cond) {}\n|s' "${ABSL_MUTEX_HEADER}"
    perl -0pi -e 's|explicit WriterMutexLock\(Mutex\* absl_nonnull mu\)\n      ABSL_EXCLUSIVE_LOCK_FUNCTION\(mu\)\n      : mu_\(mu\) \{\n    mu->WriterLock\(\);\n  \}\n|explicit WriterMutexLock(Mutex* absl_nonnull mu)\n      ABSL_EXCLUSIVE_LOCK_FUNCTION(mu)\n      : mu_(mu) {\n    mu->WriterLock();\n  }\n\n  // XLA_ABSL_MUTEX_COMPAT\n  explicit WriterMutexLock(Mutex& mu) : WriterMutexLock(&mu) {}\n|s' "${ABSL_MUTEX_HEADER}"
    perl -0pi -e 's|explicit WriterMutexLock\(Mutex& mu\) : WriterMutexLock\(&mu\) \{\}\n|explicit WriterMutexLock(Mutex& mu) : WriterMutexLock(&mu) {}\n  explicit WriterMutexLock(Mutex& mu, const Condition& cond) : WriterMutexLock(&mu, cond) {}\n|s' "${ABSL_MUTEX_HEADER}"
    perl -0pi -e 's|explicit ReleasableMutexLock\(Mutex\* absl_nonnull mu\)\n      ABSL_EXCLUSIVE_LOCK_FUNCTION\(mu\)\n      : mu_\(mu\) \{\n    this->mu_->Lock\(\);\n  \}\n|explicit ReleasableMutexLock(Mutex* absl_nonnull mu)\n      ABSL_EXCLUSIVE_LOCK_FUNCTION(mu)\n      : mu_(mu) {\n    this->mu_->Lock();\n  }\n\n  // XLA_ABSL_MUTEX_COMPAT\n  explicit ReleasableMutexLock(Mutex& mu) : ReleasableMutexLock(&mu) {}\n|s' "${ABSL_MUTEX_HEADER}"
    perl -0pi -e 's|explicit ReleasableMutexLock\(Mutex& mu\) : ReleasableMutexLock\(&mu\) \{\}\n|explicit ReleasableMutexLock(Mutex& mu) : ReleasableMutexLock(&mu) {}\n  explicit ReleasableMutexLock(Mutex& mu, const Condition& cond) : ReleasableMutexLock(&mu, cond) {}\n|s' "${ABSL_MUTEX_HEADER}"
  fi
done

cat >> .bazelrc <<EOF

build --crosstool_top=//bazel_toolchain:toolchain
build --platforms=//bazel_toolchain:target_platform
build --host_platform=//bazel_toolchain:build_platform
build --extra_toolchains=//bazel_toolchain:cc_cf_toolchain
build --extra_toolchains=//bazel_toolchain:cc_cf_host_toolchain
build --logging=6
build --verbose_failures
build --toolchain_resolution_debug
build --define=PREFIX=${PREFIX}
build --define=PROTOBUF_INCLUDE_PATH=${PREFIX}/include
build --local_resources=cpu=${CPU_COUNT}
build --define=with_cross_compiler_support=true
build --repo_env=GRPC_BAZEL_DIR=${PREFIX}/share/bazel/grpc/bazel

# We need to define a dummy value for this as we delete everything else for build_cuda_with_nvcc
build:build_cuda_with_nvcc --action_env=CONDA_USE_NVCC=1
EOF

if [[ "${target_platform}" == "osx-arm64" || "${target_platform}" != "${build_platform}" ]]; then
  echo "build --cpu=${TARGET_CPU}" >> .bazelrc
fi

# For debugging
# CUSTOM_BAZEL_OPTIONS="${CUSTOM_BAZEL_OPTIONS} --bazel_options=--subcommands"

# Force static linkage with protobuf to avoid definition collisions,
# see https://github.com/conda-forge/jaxlib-feedstock/issues/89
#
# Thus: don't add com_google_protobuf here.
export TF_SYSTEM_LIBS="boringssl,com_github_googlecloudplatform_google_cloud_cpp,com_github_grpc_grpc,flatbuffers,zlib,com_google_absl"

if [[ "${target_platform}" == "osx-64" ]]; then
    export TF_SYSTEM_LIBS="${TF_SYSTEM_LIBS},onednn"
fi

# jax-v0.8.2 can still emit CHECK_EQ on std::unique_ptr in XLA, which no longer
# type-checks with newer Abseil check-op internals.
XLA_ABSEIL_PATCH="third_party/xla/0001-Fix-abseil-headers.patch"
if [[ -f "${XLA_ABSEIL_PATCH}" ]]; then
if grep -q "xla/tsl/profiler/rpc/client/BUILD" "${XLA_ABSEIL_PATCH}"; then
awk '
  BEGIN { skip = 0 }
  /^diff --git a\/xla\/tsl\/profiler\/rpc\/client\/BUILD b\/xla\/tsl\/profiler\/rpc\/client\/BUILD$/ {
    skip = 1
    next
  }
  skip && /^diff --git / {
    skip = 0
  }
  !skip { print }
' "${XLA_ABSEIL_PATCH}" > "${XLA_ABSEIL_PATCH}.tmp"
mv "${XLA_ABSEIL_PATCH}.tmp" "${XLA_ABSEIL_PATCH}"
fi
if ! grep -q "hlo_module_group.cc" "${XLA_ABSEIL_PATCH}"; then
cat >> "${XLA_ABSEIL_PATCH}" <<'EOF'

diff --git a/xla/hlo/ir/hlo_module_group.cc b/xla/hlo/ir/hlo_module_group.cc
--- a/xla/hlo/ir/hlo_module_group.cc
+++ b/xla/hlo/ir/hlo_module_group.cc
@@ -91,1 +91,1 @@
-  CHECK_EQ(module_, nullptr);
+  CHECK(module_ == nullptr);
EOF
fi
if ! grep -q "xfeed_manager.cc" "${XLA_ABSEIL_PATCH}"; then
cat >> "${XLA_ABSEIL_PATCH}" <<'EOF'

diff --git a/xla/backends/cpu/runtime/xfeed_manager.cc b/xla/backends/cpu/runtime/xfeed_manager.cc
--- a/xla/backends/cpu/runtime/xfeed_manager.cc
+++ b/xla/backends/cpu/runtime/xfeed_manager.cc
@@ -60,1 +60,1 @@
-  absl::MutexLock l(mu_, absl::Condition(&available_buffer));
+  absl::MutexLock l(&mu_, absl::Condition(&available_buffer));
EOF
fi
if ! grep -q "shard_map_import.cc" "${XLA_ABSEIL_PATCH}"; then
cat >> "${XLA_ABSEIL_PATCH}" <<'EOF'

diff --git a/xla/service/spmd/shardy/sdy_round_trip/shard_map_import.cc b/xla/service/spmd/shardy/sdy_round_trip/shard_map_import.cc
--- a/xla/service/spmd/shardy/sdy_round_trip/shard_map_import.cc
+++ b/xla/service/spmd/shardy/sdy_round_trip/shard_map_import.cc
@@ -106,2 +106,2 @@
-    CHECK_EQ(globalToLocalShape.getCallTargetName(),
-             kGlobalToLocalShapeCallTargetName);
+    CHECK(globalToLocalShape.getCallTargetName() ==
+          kGlobalToLocalShapeCallTargetName);
EOF
fi
if ! grep -q "localToGlobalShape.getCallTargetName" "${XLA_ABSEIL_PATCH}"; then
cat >> "${XLA_ABSEIL_PATCH}" <<'EOF'

diff --git a/xla/service/spmd/shardy/sdy_round_trip/shard_map_import.cc b/xla/service/spmd/shardy/sdy_round_trip/shard_map_import.cc
--- a/xla/service/spmd/shardy/sdy_round_trip/shard_map_import.cc
+++ b/xla/service/spmd/shardy/sdy_round_trip/shard_map_import.cc
@@ -125,2 +125,2 @@
-    CHECK_EQ(localToGlobalShape.getCallTargetName(),
-             kLocalToGlobalShapeCallTargetName);
+    CHECK(localToGlobalShape.getCallTargetName() ==
+          kLocalToGlobalShapeCallTargetName);
EOF
fi
if ! grep -q "dot_handler.cc" "${XLA_ABSEIL_PATCH}"; then
cat >> "${XLA_ABSEIL_PATCH}" <<'EOF'

diff --git a/xla/service/spmd/dot_handler.cc b/xla/service/spmd/dot_handler.cc
--- a/xla/service/spmd/dot_handler.cc
+++ b/xla/service/spmd/dot_handler.cc
@@ -1973,1 +1973,1 @@
-        CHECK_EQ(e_config->windowed_op, WindowedEinsumOperand::LHS);
+        CHECK(e_config->windowed_op == WindowedEinsumOperand::LHS);
EOF
fi
if ! grep -q "user_context_registry.cc" "${XLA_ABSEIL_PATCH}"; then
cat >> "${XLA_ABSEIL_PATCH}" <<'EOF'

diff --git a/xla/python/ifrt/user_context_registry.cc b/xla/python/ifrt/user_context_registry.cc
--- a/xla/python/ifrt/user_context_registry.cc
+++ b/xla/python/ifrt/user_context_registry.cc
@@ -114,1 +114,1 @@
-  absl::WriterMutexLock lock(mu_);
+  absl::WriterMutexLock lock(&mu_);
@@ -122,1 +122,1 @@
-  absl::ReaderMutexLock lock(mu_);
+  absl::ReaderMutexLock lock(&mu_);
EOF
fi
if ! grep -q "ifrt_proxy/common/test_utils.h" "${XLA_ABSEIL_PATCH}"; then
cat >> "${XLA_ABSEIL_PATCH}" <<'EOF'

diff --git a/xla/python/ifrt_proxy/common/test_utils.h b/xla/python/ifrt_proxy/common/test_utils.h
--- a/xla/python/ifrt_proxy/common/test_utils.h
+++ b/xla/python/ifrt_proxy/common/test_utils.h
@@ -42,1 +42,1 @@
-    absl::MutexLock l(mu_);
+    absl::MutexLock l(&mu_);
@@ -50,1 +50,1 @@
-    absl::MutexLock l(mu_);
+    absl::MutexLock l(&mu_);
@@ -74,1 +74,1 @@
-    absl::MutexLock l(mu_);
+    absl::MutexLock l(&mu_);
@@ -81,1 +81,1 @@
-    absl::MutexLock l(mu_);
+    absl::MutexLock l(&mu_);
EOF
fi
if ! grep -q "concurrent_vector.h" "${XLA_ABSEIL_PATCH}"; then
cat >> "${XLA_ABSEIL_PATCH}" <<'EOF'

diff --git a/xla/tsl/concurrency/concurrent_vector.h b/xla/tsl/concurrency/concurrent_vector.h
--- a/xla/tsl/concurrency/concurrent_vector.h
+++ b/xla/tsl/concurrency/concurrent_vector.h
@@ -98,1 +98,1 @@
-    absl::MutexLock lock(mutex_);
+    absl::MutexLock lock(&mutex_);
EOF
fi
if ! grep -q "async_events_unique_id" "${XLA_ABSEIL_PATCH}"; then
cat >> "${XLA_ABSEIL_PATCH}" <<'EOF'

diff --git a/xla/backends/gpu/runtime/host_execute_thunk.cc b/xla/backends/gpu/runtime/host_execute_thunk.cc
--- a/xla/backends/gpu/runtime/host_execute_thunk.cc
+++ b/xla/backends/gpu/runtime/host_execute_thunk.cc
@@ -467,1 +467,1 @@
-  CHECK_NE(async_events_unique_id, std::nullopt);
+  CHECK(async_events_unique_id != std::nullopt);
EOF
fi
if [[ "$(grep -c "CHECK(async_events_unique_id != std::nullopt);" "${XLA_ABSEIL_PATCH}" || true)" -lt 2 ]]; then
cat >> "${XLA_ABSEIL_PATCH}" <<'EOF'

diff --git a/xla/backends/gpu/runtime/host_execute_thunk.cc b/xla/backends/gpu/runtime/host_execute_thunk.cc
--- a/xla/backends/gpu/runtime/host_execute_thunk.cc
+++ b/xla/backends/gpu/runtime/host_execute_thunk.cc
@@ -650,1 +650,1 @@
-  CHECK_NE(async_events_unique_id, std::nullopt);
+  CHECK(async_events_unique_id != std::nullopt);
EOF
fi
if ! grep -q "conditional_thunk.cc" "${XLA_ABSEIL_PATCH}"; then
cat >> "${XLA_ABSEIL_PATCH}" <<'EOF'

diff --git a/xla/backends/gpu/runtime/conditional_thunk.cc b/xla/backends/gpu/runtime/conditional_thunk.cc
--- a/xla/backends/gpu/runtime/conditional_thunk.cc
+++ b/xla/backends/gpu/runtime/conditional_thunk.cc
@@ -61,2 +61,1 @@
-  CHECK_EQ(branch_index_buffer_index.shape.dimensions(),
-           std::vector<int64_t>{});
+  CHECK(branch_index_buffer_index.shape.dimensions().empty());
EOF
fi
fi

# Mark as a release build
EXTRA="--bazel_options=--repo_env=ML_WHEEL_TYPE=release ${CUDA_ARGS:-}"

if [[ "${target_platform}" == "osx-arm64" || "${target_platform}" != "${build_platform}" ]]; then
    EXTRA="${EXTRA} --target_cpu ${TARGET_CPU}"
fi

# Never use the Appe toolchain
sed -i '/local_config_apple/d' .bazelrc
if [[ "${target_platform}" == linux-* ]]; then
    CLANG_PATH="$(command -v "${CC}" || true)"
    EXTRA="${EXTRA} --clang_path ${CLANG_PATH:-${CC}}"

    # Remove incompatible argument from bazelrc
    sed -i '/Qunused-arguments/d' .bazelrc
    # Don't override our toolchain for CUDA
    sed -i '/TF_NVCC_CLANG/{N;d}' .bazelrc
    # Keep using our toolchain
    sed -i '/--crosstool_top=@local_config_cuda/d' .bazelrc

    # Ensure host/tool C++ actions can resolve both stdlib and system headers.
    if [[ -n "${CPLUS_INCLUDE_PATH:-}" ]]; then
        echo "build --action_env=CPLUS_INCLUDE_PATH=${CPLUS_INCLUDE_PATH}" >> .bazelrc
        echo "build --host_action_env=CPLUS_INCLUDE_PATH=${CPLUS_INCLUDE_PATH}" >> .bazelrc
    fi
    if [[ -n "${LIBRARY_PATH:-}" ]]; then
        echo "build --action_env=LIBRARY_PATH=${LIBRARY_PATH}" >> .bazelrc
        echo "build --host_action_env=LIBRARY_PATH=${LIBRARY_PATH}" >> .bazelrc
    fi
fi

${PYTHON} build/build.py build \
    --target_cpu_features default \
    ${JAX_BAZEL_STARTUP_OPTIONS:+--bazel_startup_options=${JAX_BAZEL_STARTUP_OPTIONS}} \
    ${EXTRA}

# Clean up to speedup postprocessing
pushd build
# Bazel server mode can crash in this environment (Netty event loop issue).
# Cleanup is best-effort only and should not fail a successful build.
bazel --batch clean || true
popd

pushd $SP_DIR
python -m pip install $SRC_DIR/dist/jaxlib-*.whl

# Add INSTALLER file and remove RECORD, workaround for
# https://github.com/conda-forge/jaxlib-feedstock/issues/293
JAXLIB_DIST_INFO_DIR="${SP_DIR}/jaxlib-${PKG_VERSION}.dist-info"
echo "conda" > "${JAXLIB_DIST_INFO_DIR}/INSTALLER"
rm -f "${JAXLIB_DIST_INFO_DIR}/RECORD"

if [[ "${cuda_compiler_version:-None}" != "None" ]]; then
  python -m pip install $SRC_DIR/dist/jax_cuda*_plugin*.whl
  python -m pip install $SRC_DIR/dist/jax_cuda*_pjrt*.whl

  # Add INSTALLER file and remove RECORD, workaround for
  # https://github.com/conda-forge/jaxlib-feedstock/issues/293
  JAX_CUDA_PJRT_DIST_INFO_DIR="${SP_DIR}/jax_cuda${CUDA_COMPILER_MAJOR_VERSION}_pjrt-${PKG_VERSION}.dist-info"
  echo "conda" > "${JAX_CUDA_PJRT_DIST_INFO_DIR}/INSTALLER"
  rm -f "${JAX_CUDA_PJRT_DIST_INFO_DIR}/RECORD"
  JAX_CUDA_PLUGIN_DIST_INFO_DIR="${SP_DIR}/jax_cuda${CUDA_COMPILER_MAJOR_VERSION}_plugin-${PKG_VERSION}.dist-info"
  echo "conda" > "${JAX_CUDA_PLUGIN_DIST_INFO_DIR}/INSTALLER"
  rm -f "${JAX_CUDA_PLUGIN_DIST_INFO_DIR}/RECORD"

  # Regression test for https://github.com/conda-forge/jaxlib-feedstock/issues/320
  if [[ "${target_platform}" == linux-* ]]; then
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
