# import numpy as np
# from jaxlib import xla_client as xc
# xops = xc.ops

# c = xc.XlaBuilder("simple_scalar")
# param_shape = xc.Shape.array_shape(np.dtype(np.float32), ())
# x = xops.Parameter(c, 0, param_shape)
# y = xops.Sin(x)
# computation = c.Build()
# cpu_backend = xc.make_cpu_client()
# compiled_computation = cpu_backend.compile(computation)

from jaxlib import xla_client as xc

cpu_backend = xc.make_cpu_client()
compiled_computation = cpu_backend.compile_and_load(
"""
module @simple_scalar {
  func.func @main(%arg0: tensor<f32>) -> tensor<f32> {
    %0 = stablehlo.sine %arg0 : tensor<f32>
    return %0 : tensor<f32>
  }
}
""", cpu_backend.devices())
