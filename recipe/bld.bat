set BAZEL_VS="C:/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools"
set BAZEL_VC="C:/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools/VC"
set CLANG_COMPILER_PATH=%BUILD_PREFIX:\=/%/Library/bin/clang.exe
set BAZEL_LLVM=%BUILD_PREFIX:\=/%/Library/

@REM Note: TF_SYSTEM_LIBS don't work on windows per https://github.com/openxla/xla/blob/edf18ce242f234fbd20d1fbf4e9c96dfa5be2847/.bazelrc#L383

%PYTHON% build/build.py --bazel_options=--config=win_clang --verbose --use_clang=true --clang_path=%CLANG_COMPILER_PATH%
bazel clean --expunge
bazel shutdown

%PYTHON% -m pip install --find-links=dist jaxlib --no-build-isolation --no-deps

copy %PREFIX%\Lib\site-packages\jaxlib\mlir\_mlir_libs\*.dll %LIBRARY_BIN%\