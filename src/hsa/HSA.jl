module HSA

using CEnum
using hsa_rocr_jll
using LLD_jll

const libHSA_path = hsa_rocr_jll.libhsa_runtime64_path

include("low_level.jl")

function get_info(object, attribute)
    T = get_info_map(object)[attribute]
    data = T == Vector{UInt8} ? T(undef, 64) : Ref{T}()
    get_info(object, attribute, data)
    if T == Vector{UInt8}
        return unsafe_string(pointer(data))
    else
        return data[]
    end
end

function status_string(status::hsa_status_t)::String
    msg = Ref(pointer(Vector{Cchar}()))
    hsa_status_string(status, msg)
    unsafe_string(msg[])
end

function check(status::hsa_status_t)
    status == HSA_STATUS_SUCCESS && return

    msg = status_string(status)
    error("""
    HSA encountered an error.
    Status: $status.
    $(isempty(msg) ? "" : "HSA status string: $msg")
    """)
end

function break_check(status::hsa_status_t)
    (status == HSA_STATUS_SUCCESS || status == HSA_STATUS_INFO_BREAK) && return

    msg = status_string(status)
    error("""
    HSA encountered an error.
    Status: $status.
    $(isempty(msg) ? "" : "HSA status string: $msg")
    """)
end

include("device.jl")
include("isa.jl")
include("mempool.jl")
include("memregion.jl")
include("buffer.jl")
include("kernarg_buffer.jl")
include("executable.jl")
include("queue.jl")
include("signal.jl")

const REFCOUNT = Threads.Atomic{UInt64}(0)

function ref!()
    old_ref = Threads.atomic_add!(REFCOUNT, one(UInt64))
    if old_ref > typemax(UInt) - 10
        println("HSA.REFCOUNT overflow! Exiting...")
        exit(1)
    end
end

function unref!()
    old_ref = Threads.atomic_sub!(REFCOUNT, one(UInt64))
    if old_ref == 1
        hsa_shut_down() |> check
        @debug "HSA shut down successfully."
    end
end

# TODO
# - Base.show for buffer
# - Counter for Buffer-allocated memory? To get at least rough approximation

end
