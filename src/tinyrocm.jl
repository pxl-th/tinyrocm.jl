module tinyrocm

using ROCmDeviceLibs_jll
using GPUCompiler
using LLVM
using LLVM.Interop # TODO move to compiler module?

include("hsa/HSA.jl")
using .HSA

include("compiler/intrinsics/helpers.jl")
include("compiler/intrinsics/indexing.jl")
include("compiler/dims.jl")
include("compiler/device_libs.jl")
include("compiler/gpucompiler.jl")
include("compiler/kernel.jl")
include("compiler/execution.jl")

function __init__()
    HSA.hsa_init() |> HSA.check
    @debug "HSA initialized successfully."
    HSA.ref!()
    atexit(() -> HSA.unref!())
    HSA.set_default_device()
end

function kern!()
    i = workgroupIdx().x
    return nothing
end

function main()
    device = HSA.Device()
    signal = HSA.Signal()
    queue = HSA.Queue()

    @time kernel = rocfunction(kern!; device)
    @time kernel(queue, signal; groupsize=128, gridsize=128)
    @time wait(signal)

    # @show device

    # isa = HSA.get_isas(device)[1]
    # @show isa
    # @show HSA.profile(isa)

    # for pool in HSA.get_memory_pools(device)
    #     @show pool
    # end

    # x = Float32[1, 2, 3]
    # y = Float32[0, 0, 0]

    # buffer = HSA.Buffer(device, 0)
    # @show HSA.is_valid(buffer)

    # buffer = HSA.Buffer(device, sizeof(x))
    # @show HSA.is_valid(buffer)

    # info = HSA.info(buffer)
    # @show Int(info.sizeInBytes)

    # HSA.upload!(buffer, pointer(x), sizeof(x))
    # HSA.download(buffer, pointer(y), sizeof(y))
    # @show x
    # @show y

    # HSA.free(buffer)
    nothing
end

end
