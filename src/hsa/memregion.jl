const REGION_INFO_MAP = Dict(
    HSA_REGION_INFO_SEGMENT => hsa_region_segment_t,
    HSA_REGION_INFO_GLOBAL_FLAGS => hsa_region_global_flag_t,
    HSA_REGION_INFO_SIZE => UInt64,
    HSA_REGION_INFO_ALLOC_MAX_SIZE => UInt64,
    HSA_REGION_INFO_ALLOC_MAX_PRIVATE_WORKGROUP_SIZE => UInt32,
    HSA_REGION_INFO_RUNTIME_ALLOC_ALLOWED => Bool,
    HSA_REGION_INFO_RUNTIME_ALLOC_GRANULE => UInt64,
    HSA_REGION_INFO_RUNTIME_ALLOC_ALIGNMENT => UInt64,
)

function get_info(region::hsa_region_t, attribute, data)
    hsa_region_get_info(region, attribute, data) |> check
end

get_info_map(::hsa_region_t) = REGION_INFO_MAP

struct MemoryRegion
    region::hsa_region_t
end

raw(r::MemoryRegion) = r.region

handle(r::MemoryRegion) = r.region.handle

segment(r::MemoryRegion)::hsa_region_segment_t = get_info(raw(r), HSA_REGION_INFO_SEGMENT)

global_flags(r::MemoryRegion)::hsa_region_global_flag_t = get_info(raw(r), HSA_REGION_INFO_GLOBAL_FLAGS)

size(r::MemoryRegion)::UInt64 = get_info(raw(r), HSA_REGION_INFO_SIZE)

max_size(r::MemoryRegion)::UInt64 = get_info(raw(r), HSA_REGION_INFO_ALLOC_MAX_SIZE)

max_private_workgroup_size(r::MemoryRegion)::UInt32 = get_info(raw(r), HSA_REGION_INFO_ALLOC_MAX_PRIVATE_WORKGROUP_SIZE)

alloc_allowed(r::MemoryRegion)::Bool = get_info(raw(r), HSA_REGION_INFO_RUNTIME_ALLOC_ALLOWED)

alloc_granule(r::MemoryRegion)::UInt64 = get_info(raw(r), HSA_REGION_INFO_RUNTIME_ALLOC_GRANULE)

alloc_alignment(r::MemoryRegion)::UInt64 = get_info(raw(r), HSA_REGION_INFO_RUNTIME_ALLOC_ALIGNMENT)

function get_memory_regions(device::Device)
    function _callback(region::hsa_region_t, regions::Vector{MemoryRegion})
        push!(regions, MemoryRegion(region))
        return HSA_STATUS_SUCCESS
    end
    ccallback = @cfunction($_callback,
        hsa_status_t, (hsa_region_t, Ref{Vector{MemoryRegion}}))
    regions = Ref(Vector{MemoryRegion}())
    hsa_agent_iterate_regions(raw(device), ccallback, regions) |> check
    regions[]
end

function get_memory_region(
    device::Device;
    flag::hsa_region_global_flag_t = HSA_REGION_GLOBAL_FLAG_KERNARG,
)
    regions = filter(r -> (global_flags(r) & flag) > 0,
        get_memory_regions(device))
    isempty(regions) && error("""Failed to find region for `$flag` flag.
        Device: $device.
    """)
    first(regions)
end

function allocate(r::MemoryRegion, bytesize::Int)
    ptr = Ref{Ptr{Cvoid}}()
    hsa_memory_allocate(raw(r), bytesize, ptr) |> check
    ptr[]
end

function Base.show(io::IO, region::MemoryRegion)
    seg = segment(region)
    is_private = seg == HSA_REGION_SEGMENT_PRIVATE
    pws::UInt64 = is_private ? max_private_workgroup_size(region) : 0
    pws_string = is_private ?
        "\n- Max private workgroup size: $(Base.format_bytes(pws))\n" : ""

    flags = global_flags(region)
    println(io, """MemoryRegion @ $(handle(region)) handle
        - Segment: $seg
        - Global flags: $flags ($(UInt32(flags)) as UInt32)
        - Size: $(Base.format_bytes(size(region)))
        - Max size: $(Base.format_bytes(max_size(region))) $pws_string
        - Alloc allowed: $(alloc_allowed(region))
        - Alloc granule: $(Base.format_bytes(alloc_granule(region)))
        - Alloc alignment: $(Base.format_bytes(alloc_alignment(region)))
    """)
end
