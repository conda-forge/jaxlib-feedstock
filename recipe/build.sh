#!/bin/bash

set -euxo pipefail

if [[ "${target_platform}" == osx-* ]]; then
  export LDFLAGS="${LDFLAGS} -lz -framework CoreFoundation -Xlinker -undefined -Xlinker dynamic_lookup"
else
  export LDFLAGS="${LDFLAGS} -lrt"
fi
source ${RECIPE_DIR}/gen-bazel-toolchain.sh
${PYTHON} build/build.py --target_cpu_features default --enable_mkl_dnn --bazel_options " --crosstool_top=//custom_toolchain:toolchain --logging=6 --verbose_failures" --target_cpu ${TARGET_CPU}
${PYTHON} -m pip install dist/jaxlib-*.whl
