const _rocfunction_cache::Dict{HSA.Device, Dict{UInt64, HSA.Executable}} =
    Dict{HSA.Device, Dict{UInt64, HSA.Executable}}()

function rocfunction_cache(device::HSA.Device)
    get!(() -> Dict{UInt64, HSA.Executable}(), _rocfunction_cache, device)
end

function rocfunction(
    f::F, tt::Type = Tuple{};
    name = nothing, device::HSA.Device = HSA.Device(),
) where F <: Function
    cache = rocfunction_cache(device)
    isa = HSA.default_isa(device)
    dev_isa, features = HSA.llvm_arch_features(isa)

    source = FunctionSpec(F, tt, true, name)
    target = GCNCompilerTarget(; dev_isa, features)
    params = ROCCompilerParams(device)
    job = CompilerJob(target, source, params; always_inline=true)

    exe::HSA.Executable = GPUCompiler.cached_compilation(
        cache, job, rocfunction_compile, rocfunction_link)
    Kernel(f, exe)
end

function rocfunction_compile(@nospecialize(job::CompilerJob))
    JuliaContext() do ctx
        rocfunction_compile(job, ctx)
    end
end

function rocfunction_compile(@nospecialize(job::CompilerJob), ctx)
    mi, mi_meta = GPUCompiler.emit_julia(job)
    ir, ir_meta = GPUCompiler.emit_llvm(job, mi; ctx)
    obj, obj_meta = GPUCompiler.emit_asm(job, ir; format=LLVM.API.LLVMObjectFile)
    entry = LLVM.name(ir_meta.entry)

    globals = map(
        g -> Symbol(LLVM.name(g)) => LLVM.llvmtype(g), # TODO finish
        filter(x -> LLVM.isextinit(x), collect(LLVM.globals(ir))))
    @assert isempty(globals) # TODO handle when non empty

    (; obj, entry)
end

function rocfunction_link(@nospecialize(job::CompilerJob), compiled)
    device = job.params.device
    (; obj, entry) = compiled

    exe = HSA.Executable(device, codeunits(obj), entry)
    # TODO initialize globals from hooks
    exe
end
