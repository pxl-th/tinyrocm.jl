const POOL_INFO_MAP = Dict(
    HSA_AMD_MEMORY_POOL_INFO_SEGMENT => hsa_amd_segment_t,
    HSA_AMD_MEMORY_POOL_INFO_GLOBAL_FLAGS => hsa_amd_memory_pool_global_flag_t,
    HSA_AMD_MEMORY_POOL_INFO_SIZE => UInt64,
    HSA_AMD_MEMORY_POOL_INFO_RUNTIME_ALLOC_ALLOWED => Bool,
    HSA_AMD_MEMORY_POOL_INFO_RUNTIME_ALLOC_GRANULE => UInt64,
    HSA_AMD_MEMORY_POOL_INFO_RUNTIME_ALLOC_ALIGNMENT => UInt64,
    HSA_AMD_MEMORY_POOL_INFO_ACCESSIBLE_BY_ALL => Bool,
    HSA_AMD_MEMORY_POOL_INFO_ALLOC_MAX_SIZE => UInt64,
)

function get_info(pool::hsa_amd_memory_pool_t, attribute, data)
    hsa_amd_memory_pool_get_info(pool, attribute, data) |> check
end

get_info_map(::hsa_amd_memory_pool_t) = POOL_INFO_MAP

struct MemoryPool
    pool::hsa_amd_memory_pool_t
end

raw(p::MemoryPool)::UInt64 = p.pool

handle(p::MemoryPool)::UInt64 = p.pool.handle

segment(p::MemoryPool)::hsa_amd_segment_t = get_info(raw(p), HSA_AMD_MEMORY_POOL_INFO_SEGMENT)

global_flags(p::MemoryPool)::hsa_amd_memory_pool_global_flag_t = get_info(raw(p), HSA_AMD_MEMORY_POOL_INFO_GLOBAL_FLAGS)

size(p::MemoryPool)::UInt64 = get_info(raw(p), HSA_AMD_MEMORY_POOL_INFO_SIZE)

alloc_allowed(p::MemoryPool)::Bool = get_info(raw(p), HSA_AMD_MEMORY_POOL_INFO_RUNTIME_ALLOC_ALLOWED)

alloc_granule(p::MemoryPool)::UInt64 = get_info(raw(p), HSA_AMD_MEMORY_POOL_INFO_RUNTIME_ALLOC_GRANULE)

alloc_alignment(p::MemoryPool)::UInt64 = get_info(raw(p), HSA_AMD_MEMORY_POOL_INFO_RUNTIME_ALLOC_ALIGNMENT)

accessible_by_all(p::MemoryPool)::Bool = get_info(raw(p), HSA_AMD_MEMORY_POOL_INFO_ACCESSIBLE_BY_ALL)

max_size(p::MemoryPool)::UInt64 = get_info(raw(p), HSA_AMD_MEMORY_POOL_INFO_ALLOC_MAX_SIZE)

function get_memory_pools(device::Device)
    function _callback(pool::hsa_amd_memory_pool_t, pools::Vector{MemoryPool})
        push!(pools, MemoryPool(pool))
        return HSA_STATUS_SUCCESS
    end
    ccallback = @cfunction($_callback,
        hsa_status_t, (hsa_amd_memory_pool_t, Ref{Vector{MemoryPool}}))
    pools = Ref(Vector{MemoryPool}())
    hsa_amd_agent_iterate_memory_pools(raw(device), ccallback, pools) |> check
    pools[]
end

function get_memory_pool(
    device::Device;
    flag::hsa_amd_memory_pool_global_flag_t = HSA_AMD_MEMORY_POOL_GLOBAL_FLAG_COARSE_GRAINED,
)
    pools = get_memory_pools(device)
    idx = findfirst(p -> global_flags(p) == flag, pools)
    isnothing(idx) && error("""
        No memory pool for `flag=$flag` in `device=$device`.
    """)
    pools[idx]
end

function allocate(pool::MemoryPool, bytesize::Int)
    ptr = Ref{Ptr{Cvoid}}()
    hsa_amd_memory_pool_allocate(raw(pool), bytesize, zero(UInt32), ptr) |> check
    ptr[]
end

function Base.show(io::IO, pool::MemoryPool)
    println(io, """MemoryPool @ $(handle(pool)) handle
        - Segment: $(segment(pool))
        - Global flags: $(global_flags(pool))
        - Alloc allowed: $(alloc_allowed(pool))
        - Alloc granule: $(Base.format_bytes(alloc_granule(pool)))
        - Alloc alignment: $(Base.format_bytes(alloc_alignment(pool)))
        - Accessible by all: $(accessible_by_all(pool))
        - Size: $(Base.format_bytes(size(pool))) bytes
        - Max aggregate size: $(Base.format_bytes(max_size(pool))) bytes
    """)
end
