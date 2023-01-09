# tinyrocm.jl

Minimal implementation of AMDGPU ROCm programming in Julia from scratch. <br/>
For learning purposes, [AMDGPU.jl](https://github.com/JuliaGPU/AMDGPU.jl) was user as a reference.

Supports simplest kernels at the moment:

```julia
function kern!()
    i = workgroupIdx().x
    return nothing
end

device = HSA.Device()
signal = HSA.Signal()
queue = HSA.Queue()

@time kernel = rocfunction(kern!)
@time kernel(queue, signal; groupsize=128, gridsize=1024)
@time wait(signal)
```
