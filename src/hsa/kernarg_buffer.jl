mutable struct KernargBuffer
    ptr::Ptr{Cvoid}
    device::Device
    region::MemoryRegion
    bytesize::Int
end

function KernargBuffer(device::Device, bytesize::Int)
    bytesize == 0 && return KernargBuffer(
        C_NULL, device, MemoryRegion(hsa_region_t(0)), 0)

    region = get_memory_region(device)
    ptr = allocate(region, bytesize)
    buffer = KernargBuffer(ptr, device, region, bytesize)

    ref!()
    finalizer(buffer) do b
        free(b)
    end
    buffer
end

function free(b::KernargBuffer)
    hsa_memory_free(b.ptr) |> check
end

raw(b::KernargBuffer) = b.ptr

is_valid(b::KernargBuffer) = b.ptr != C_NULL

Base.isempty(b::KernargBuffer) = b.bytesize == 0

function write_args!(b::KernargBuffer, args...)
    isempty(b) && return nothing
    @assert false # TODO
    nothing
end
