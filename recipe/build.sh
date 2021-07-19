#!/bin/bash

set -euxo pipefail

if [[ "${target_platform}" == osx-* ]]; then
  export LDFLAGS="${LDFLAGS} -lz -framework CoreFoundation -Xlinker -undefined -Xlinker dynamic_lookup"
else
  export LDFLAGS="${LDFLAGS} -lrt"
fi
source ${RECIPE_DIR}/gen-bazel-toolchain.sh
if [[ "${target_platform}" == linux-* ]]; then
  ${PYTHON} build/build.py --target_cpu_features default --enable_mkl_dnn --bazel_options " --crosstool_top=//custom_toolchain:toolchain --logging=6 --verbose_failures --cpu ${TARGET_CPU}"
else
  ${PYTHON} build/build.py --target_cpu_features default --enable_mkl_dnn --bazel_options " --crosstool_top=//custom_toolchain:toolchain --logging=6 --verbose_failures" --target_cpu ${TARGET_CPU}
fi
${PYTHON} -m pip install dist/jaxlib-*.whl
