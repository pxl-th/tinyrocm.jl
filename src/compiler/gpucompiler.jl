@static if isdefined(Base.Experimental, Symbol("@overlay"))
    Base.Experimental.@MethodTable(method_table)
else
    const method_table = nothing
end

struct ROCCompilerParams <: GPUCompiler.AbstractCompilerParams
    device::HSA.Device
    # TODO global hooks who dis?
end

const CI_CACHE = GPUCompiler.CodeCache()

const ROCCompilerJob = CompilerJob{GCNCompilerTarget, ROCCompilerParams}

GPUCompiler.runtime_module(::ROCCompilerJob) = ROCM

GPUCompiler.ci_cache(::ROCCompilerJob) = CI_CACHE

GPUCompiler.method_table(::ROCCompilerJob) = method_table

# TODO KernelState

# Filter-out functions from device libs.
function GPUCompiler.isintrinsic(@nospecialize(job::ROCCompilerJob), fn::String)
    invoke(GPUCompiler.isintrinsic,
        Tuple{CompilerJob{GCNCompilerTarget}, typeof(fn)},
        job, fn) || startswith("rocm")
end

function GPUCompiler.link_libraries!(
    @nospecialize(job::ROCCompilerJob), mod::LLVM.Module,
    undefined_fns::Vector{String},
)
    invoke(GPUCompiler.link_libraries!,
        Tuple{CompilerJob{GCNCompilerTarget}, typeof(mod), typeof(undefined_fns)},
        job, mod, undefined_fns)
    link_device_libs!(job.target, mod)
end
