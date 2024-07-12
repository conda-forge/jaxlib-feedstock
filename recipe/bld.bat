@echo on

set "BAZEL_SH=%BUILD_PREFIX%\Library\usr\bin\bash.exe"

@rem echo "build --local_cpu_resources=1" >> .bazelrc
echo --extra_toolchains=@local_config_cc//:cc-toolchain-x64_windows-clang-cl >> .bazelrc
echo --extra_execution_platforms=//jax/tools/toolchains:x64_windows-clang-cl >> .bazelrc
echo --compiler=clang-cl >> .bazelrc

type .bazelrc

%PYTHON% build/build.py --target_cpu_features default --enable_mkl_dnn
if %ERRORLEVEL% neq 0 exit 1

@rem Clean up to speedup postprocessing
pushd build
bazel clean
popd

pushd %SP_DIR%
exit 1
@rem pip doesn't want to install cleanly in all cases, so we use the fact that we can unzip it.
@rem Fix this for Windows
@rem unzip $SRC_DIR/dist/jaxlib-*.whl
popd
