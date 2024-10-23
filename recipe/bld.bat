set BAZEL_VS=C:/Program Files/Microsoft Visual Studio/2022/BuildTools 
set BAZEL_VC=C:/Program Files/Microsoft Visual Studio/2022/BuildTools/VC
set CLANG_COMPILER_PATH=%BUILD_PREFIX:\=/%/Library/bin/clang.exe
set BAZEL_LLVM=%BUILD_PREFIX:\=/%/Library/

%PYTHON% build/build.py --bazel_options=--config=win_clang --verbose --use_clang=true --clang_path=%BUILD_PREFIX:\=/%/Library/bin/clang.exe
bazel clean --expunge
bazel shutdown

%PYTHON% -m pip install --find-links=dist jaxlib --no-build-isolation --no-deps

copy %PREFIX%\Lib\site-packages\jaxlib\mlir\_mlir_libs\*.dll %LIBRARY_BIN%\