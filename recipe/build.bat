@echo on
%PYTHON% build/build.py build --target_cpu_features default --wheels=jaxlib
if %ERRORLEVEL% neq 0 exit 1

