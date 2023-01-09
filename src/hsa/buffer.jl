struct Buffer
    ptr::Ptr{Cvoid}
    device::Device
    pool::MemoryPool
    bytesize::Int
end

function Buffer(device::Device, bytesize::Int)
    bytesize == 0 && return Buffer(
        C_NULL, device, MemoryPool(hsa_amd_memory_pool_t(0)), 0)

    pool = get_memory_pool(device)
    ptr = allocate(pool, bytesize)
    Buffer(ptr, device, pool, bytesize)
end

function free(b::Buffer)
    hsa_amd_memory_pool_free(b.ptr) |> check
end

is_valid(b::Buffer) = b.ptr != C_NULL

function info(b::Buffer)
    ptr_info = Ref{hsa_amd_pointer_info_t}()
    # Set `size` field to `sizeof(hsa_amd_pointer_info_t)` as required.
    ptr_info_ptr = Base.unsafe_convert(Ptr{hsa_amd_pointer_info_t}, ptr_info)
    unsafe_store!(
        reinterpret(Ptr{UInt32}, ptr_info_ptr),
        sizeof(hsa_amd_pointer_info_t))

    hsa_amd_pointer_info(
        b.ptr, ptr_info, C_NULL, Ptr{UInt32}(C_NULL), C_NULL) |> check
    ptr_info[]
end

function upload!(b::Buffer, src::Ptr, bytesize::Int)
    bytesize == 0 && return
    HSA.hsa_memory_copy(b.ptr, Ptr{Cvoid}(src), bytesize) |> check
end

function download(b::Buffer, dst::Ptr, bytesize::Int)
    bytesize == 0 && return
    HSA.hsa_memory_copy(Ptr{Cvoid}(dst), b.ptr, bytesize) |> check
end

function transfer!(dst::Buffer, src::Buffer, bytesize::Int)
    upload!(dst, src.ptr, bytesize)
end
