from jaxlib import xla_client as xc

cpu_backend = xc.make_cpu_client()
compiled_computation = cpu_backend.compile(
"""
module @simple_scalar {
  func.func @main(%arg0: tensor<f32>) -> tensor<f32> {
    %0 = stablehlo.sine %arg0 : tensor<f32>
    return %0 : tensor<f32>
  }
}
""")