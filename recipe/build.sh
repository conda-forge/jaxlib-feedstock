#!/bin/bash

set -euxo pipefail

# TODO(features):
# * --enable_mkl_dnn
# * --enable_cuda
# * --enable_rocm
# * --target_cpu_features (different settings depending on archspec)
# TODO: Use bazel from conda-forge
# TODO: This currently bundles:
# * LLVM
# * MLIR
# * protobuf
# * mkl_dnn_v1 (nowadays called oneDNN)
${PYTHON} build/build.py --target_cpu_features default
${PYTHON} -m pip install dist/jaxlib-*.whl
