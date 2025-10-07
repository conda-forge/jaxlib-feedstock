@echo on

set "PREFIX_CYG=%PREFIX:\=/%"
set "PREFIX_CYG=/%PREFIX_CYG::=%"

echo "build --repo_env=GRPC_BAZEL_DIR=%PREFIX_CYG%/share/bazel/grpc/bazel" >> .bazelrc
echo "" >> .bazelrc
if %ERRORLEVEL% neq 0 exit 1
type .bazelrc

%PYTHON% build/build.py build --target_cpu_features default --wheels=jaxlib
if %ERRORLEVEL% neq 0 exit 1

