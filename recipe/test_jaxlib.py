import numpy as np
from jaxlib import xla_client as xc
xops = xc.ops

c = xc.XlaBuilder("simple_scalar")
param_shape = xc.Shape.array_shape(np.dtype(np.float32), ())
x = xops.Parameter(c, 0, param_shape)
y = xops.Sin(x)
computation = c.Build()
cpu_backend = xc.make_cpu_client()
compiled_computation = cpu_backend.compile(computation)
