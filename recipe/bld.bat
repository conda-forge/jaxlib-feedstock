%PYTHON% build/build.py
bazel clean --expunge
bazel shutdown

%PYTHON% -m pip install dist/jaxlib-*.whl --no-build-isolation --no-deps