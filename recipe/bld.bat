@echo on

set "BAZEL_SH=%BUILD_PREFIX%\Library\usr\bin\bash.exe"

echo "build --local_cpu_resources=1" >> .bazelrc

@rem Debug information, can be commented
type .bazelrc
set

@rem set "TF_SYSTEM_LIBS=boringssl,com_github_googlecloudplatform_google_cloud_cpp,com_github_grpc_grpc,flatbuffers,zlib"
set "TF_SYSTEM_LIBS=boringssl,com_github_googlecloudplatform_google_cloud_cpp,com_github_grpc_grpc,flatbuffers"

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

