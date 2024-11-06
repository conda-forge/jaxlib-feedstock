set BAZEL_VS="%VSINSTALLDIR%"
set BAZEL_VC="%VSINSTALLDIR%/VC"
set CLANG_COMPILER_PATH=%BUILD_PREFIX:\=/%/Library/bin/clang.exe
set BAZEL_LLVM=%BUILD_PREFIX:\=/%/Library/

@REM   - if JAX_RELEASE or JAXLIB_RELEASE are set: version looks like "0.4.16"
@REM   - if JAX_NIGHTLY or JAXLIB_NIGHTLY are set: version looks like "0.4.16.dev20230906"
@REM   - if none are set: version looks like "0.4.16.dev20230906+ge58560fdc
set JAXLIB_RELEASE=1

@REM Note: TF_SYSTEM_LIBS don't work on windows per https://github.com/openxla/xla/blob/edf18ce242f234fbd20d1fbf4e9c96dfa5be2847/.bazelrc#L383

%PYTHON% build/build.py --bazel_options=--config=win_clang --verbose --use_clang=true --clang_path=%CLANG_COMPILER_PATH%
bazel clean --expunge
bazel shutdown

%PYTHON% -m pip install --find-links=dist jaxlib --no-build-isolation --no-deps

copy %PREFIX%\Lib\site-packages\jaxlib\mlir\_mlir_libs\*.dll %LIBRARY_BIN%\