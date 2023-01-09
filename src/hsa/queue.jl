mutable struct Queue
    queue::Ptr{hsa_queue_t}
    status::hsa_status_t
    device::Device
    size::UInt32
end

function _queue_error_handler(
    status::hsa_status_t, ::Ptr{hsa_queue_t}, queue_ptr::Ptr{Cvoid},
)::Nothing
    status == HSA_STATUS_SUCCESS && return nothing
    queue::Queue = unsafe_pointer_to_objref(queue_ptr)
    queue.status = status
    return nothing
end

function Queue(device::Device)
    ccallback = @cfunction(_queue_error_handler,
        Cvoid, (hsa_status_t, Ptr{hsa_queue_t}, Ptr{Cvoid}))

    queue_size = max_queue_size(device)
    queue = Queue(Ptr{hsa_queue_t}(C_NULL), HSA_STATUS_SUCCESS, device, queue_size)

    # TODO support queue multi type
    queue_ref = Ref{Ptr{hsa_queue_t}}()
    hsa_queue_create(
        device.agent, queue_size, HSA_QUEUE_TYPE_SINGLE,
        ccallback, pointer_from_objref(queue),
        typemax(UInt32), typemax(UInt32), queue_ref) |> check

    queue.queue = queue_ref[]

    ref!()
    finalizer(queue) do q
        destroy!(q)
        unref!()
    end
    queue
end

Queue() = Queue(Device())

raw(q::Queue) = q.queue

function destroy!(q::Queue)
    # TODO set `active` to false
    # TODO check for exceptions
    # TODO delete from global active queues
    hsa_queue_destroy(raw(q)) |> check
end

function get_write_idx(q::Queue)::UInt64
    write_idx = hsa_queue_add_write_index_screlease(raw(q), one(UInt64))
    read_idx = hsa_queue_load_read_index_scacquire(raw(q))
    # Yield until queue is not full.
    while (write_idx - read_idx) ≥ q.size
        yield()
        read_idx = hsa_queue_load_read_index_scacquire(raw(q))
    end
    write_idx
end

function get_write_address(
    queue::hsa_queue_t, write_idx::UInt64, ::Type{P},
) where P
    @assert sizeof(P) == 64
    base_addr = Ptr{hsa_kernel_dispatch_packet_t}(queue.base_address)
    base_addr + sizeof(P) * (write_idx % queue.size)
end

function dispatch!(f, q::Queue, ::Type{P}) where P
    packet = Ref{P}(f())

    write_idx = get_write_idx(q)
    raw_queue = unsafe_load(q.queue)::hsa_queue_t
    packet_address = get_write_address(raw_queue, write_idx, P)

    # Copy packet to its address on queue.
    packet_ptr = convert(
        Ptr{hsa_kernel_dispatch_packet_t},
        Base.unsafe_convert(Ptr{P}, packet))
    unsafe_copyto!(packet_address, packet_ptr, 1)

    # TODO: Generalize to allow barrier on kernel
    _header(::Type{hsa_kernel_dispatch_packet_t}) = HSA_PACKET_TYPE_KERNEL_DISPATCH
    _header(::Type{hsa_barrier_and_packet_t}) = HSA_PACKET_TYPE_BARRIER_AND
    _header(::Type{hsa_barrier_or_packet_t}) = HSA_PACKET_TYPE_BARRIER_OR

    # Create header.
    header::UInt16 = zero(UInt16)
    header |= UInt16(_header(P)) << UInt16(HSA_PACKET_HEADER_TYPE)
    header |= UInt16(HSA_FENCE_SCOPE_SYSTEM) << UInt16(HSA_PACKET_HEADER_SCACQUIRE_FENCE_SCOPE)
    header |= UInt16(HSA_FENCE_SCOPE_SYSTEM) << UInt16(HSA_PACKET_HEADER_SCRELEASE_FENCE_SCOPE)
    # Atomically write header field to packet.
    _atomic_store_header!(
        Base.unsafe_convert(Ptr{UInt16}, packet_address), header)

    # Ring the doorbell to dispatch the kernel.
    packet_id = Int64(write_idx)
    @assert write_idx == packet_id
    hsa_signal_store_screlease(raw_queue.doorbell_signal, packet_id)
    return nothing
end

# Atomic store using LLVM intrinsics
# Necessary for writing the AQL packet header to the queue
# prior to launching a kernel.
@eval function _atomic_store_header!(x::Ptr{UInt16}, v::UInt16)
    Base.llvmcall($"""
    %ptr = inttoptr i$(Sys.WORD_SIZE) %0 to i16*
    store atomic i16 %1, i16* %ptr release, align 64
    ret void
    """, Cvoid, Tuple{Ptr{UInt16}, UInt16}, x, v)
end
