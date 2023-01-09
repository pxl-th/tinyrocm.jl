const EXECUTABLE_SYMBOL_INFO_MAP = Dict(
    HSA_EXECUTABLE_SYMBOL_INFO_TYPE => hsa_symbol_kind_t,
    HSA_EXECUTABLE_SYMBOL_INFO_KERNEL_OBJECT => UInt64,
    HSA_EXECUTABLE_SYMBOL_INFO_KERNEL_KERNARG_SEGMENT_SIZE => UInt32,
    HSA_EXECUTABLE_SYMBOL_INFO_KERNEL_KERNARG_SEGMENT_ALIGNMENT => UInt32,
    HSA_EXECUTABLE_SYMBOL_INFO_KERNEL_GROUP_SEGMENT_SIZE => UInt32,
    HSA_EXECUTABLE_SYMBOL_INFO_KERNEL_PRIVATE_SEGMENT_SIZE => UInt32,
)

function get_info(symbol::hsa_executable_symbol_t, attribute, data)
    hsa_executable_symbol_get_info(symbol, attribute, data) |> check
end

get_info_map(::hsa_executable_symbol_t) = EXECUTABLE_SYMBOL_INFO_MAP

kernel_object(symbol::hsa_executable_symbol_t)::UInt64 = get_info(symbol, HSA_EXECUTABLE_SYMBOL_INFO_KERNEL_OBJECT)

kernarg_segment_size(symbol::hsa_executable_symbol_t)::UInt32 = get_info(symbol, HSA_EXECUTABLE_SYMBOL_INFO_KERNEL_KERNARG_SEGMENT_SIZE)

kernarg_segment_alignment(symbol::hsa_executable_symbol_t)::UInt32 = get_info(symbol, HSA_EXECUTABLE_SYMBOL_INFO_KERNEL_KERNARG_SEGMENT_ALIGNMENT)

group_segment_size(symbol::hsa_executable_symbol_t)::UInt32 = get_info(symbol, HSA_EXECUTABLE_SYMBOL_INFO_KERNEL_GROUP_SEGMENT_SIZE)

private_segment_size(symbol::hsa_executable_symbol_t)::UInt32 = get_info(symbol, HSA_EXECUTABLE_SYMBOL_INFO_KERNEL_PRIVATE_SEGMENT_SIZE)

mutable struct Executable
    device::Device
    symbol::String
    executable::Ref{hsa_executable_t}
    reader::Ref{hsa_code_object_reader_t}
    global_buffers::Dict{Symbol, Buffer} # TODO
end

function Executable(device::Device, data::Vector{UInt8}, symbol::String)
    # TODO globals
    reader, raw_exe, global_buffers = _create_executable(device, data, symbol)
    executable = Executable(device, symbol, raw_exe, reader, global_buffers)

    ref!()
    finalizer(executable) do exe
        hsa_executable_destroy(exe.executable[]) |> check
        hsa_code_object_reader_destroy(exe.reader[]) |> check
        for b in values(exe.global_buffers)
            free(b)
        end
        unref!()
    end
    executable
end

function Executable(
    device::Device, obj::Base.CodeUnits{UInt8, String}, symbol::String,
    # TODO globals
)
    exe_path = mktemp() do path, io
        write(io, obj)
        flush(io)
        exe_path = path * ".exe"
        LLD_jll.lld() do lld
            run(`$lld -flavor gnu -shared -o $exe_path $path`)
        end
        exe_path
    end
    data = read(exe_path)
    rm(exe_path)
    Executable(device, data, symbol)
end

raw(exe::Executable) = exe.executable[]

function kernel_symbol(exe::Executable)
    function _callback(
        executable::hsa_executable_t, agent::hsa_agent_t,
        symbol::hsa_executable_symbol_t, data::Ptr{hsa_executable_symbol_t},
    )::hsa_status_t
        type = get_info(symbol, HSA_EXECUTABLE_SYMBOL_INFO_TYPE)
        type != HSA_SYMBOL_KIND_KERNEL && return HSA_STATUS_SUCCESS
        unsafe_store!(data, symbol)
        return HSA_STATUS_INFO_BREAK
    end
    ccallback = @cfunction($_callback, hsa_status_t,
        (hsa_executable_t, hsa_agent_t, hsa_executable_symbol_t, Ptr{hsa_executable_symbol_t}))

    symbol = Ref{hsa_executable_symbol_t}()
    hsa_executable_iterate_agent_symbols(
        raw(exe), raw(exe.device), ccallback, symbol) |> break_check
    symbol[]
end

function _create_executable(
    device::Device, data::Vector{UInt8}, symbol::String;
    globals::Dict{Symbol, Int} = Dict{Symbol, Int}(),
)
    isa = default_isa(device)

    reader = Ref{hsa_code_object_reader_t}(hsa_code_object_reader_t(0))
    hsa_code_object_reader_create_from_memory(
        data, sizeof(data), reader) |> check

    executable = Ref{hsa_executable_t}()
    hsa_executable_create_alt( # TODO get rounding mode from isa
        profile(isa), HSA_DEFAULT_FLOAT_ROUNDING_MODE_NEAR,
        C_NULL, executable) |> check

    global_buffers = Dict{Symbol, Buffer}() # TODO process globals
    @assert isempty(globals)

    hsa_executable_load_agent_code_object(
        executable[], device.agent, reader[], C_NULL, C_NULL) |> check
    hsa_executable_freeze(executable[], C_NULL) |> check

    valid = Ref{UInt32}()
    hsa_executable_validate_alt(executable[], C_NULL, valid) |> check
    valid[] == 0 || error("""HSA executable with `$symbol` symbol is not valid.
        Validation code: $(valid[]), must be `0` to be valid.
    """)

    reader, executable, global_buffers
end

# TODO show method
