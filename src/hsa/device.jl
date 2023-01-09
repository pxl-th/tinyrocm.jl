const AGENT_INFO_MAP = Dict(
    HSA_AGENT_INFO_NAME => Vector{UInt8},
    HSA_AGENT_INFO_VENDOR_NAME => Vector{UInt8},
    HSA_AGENT_INFO_DEVICE => hsa_device_type_t,
        # Deprecated, use ISA.
        HSA_AGENT_INFO_WAVEFRONT_SIZE => UInt32,
        HSA_AGENT_INFO_WORKGROUP_MAX_DIM => UInt32,
        HSA_AGENT_INFO_WORKGROUP_MAX_SIZE => UInt32,
        HSA_AGENT_INFO_QUEUE_TYPE => hsa_queue_type_t,
        HSA_AGENT_INFO_QUEUE_MIN_SIZE => UInt32,
        HSA_AGENT_INFO_QUEUE_MAX_SIZE => UInt32,
    # AMD extensions.
    HSA_AMD_AGENT_INFO_UUID => Vector{UInt8},
    HSA_AMD_AGENT_INFO_PRODUCT_NAME => Vector{UInt8},
    HSA_AMD_AGENT_INFO_COMPUTE_UNIT_COUNT => UInt32,
    HSA_AMD_AGENT_INFO_NUM_SIMDS_PER_CU => UInt32,
)

function get_info(agent::hsa_agent_t, attribute, data)
    hsa_agent_get_info(agent, UInt32(attribute), data) |> check
end

get_info_map(::hsa_agent_t) = AGENT_INFO_MAP

struct Device
    agent::hsa_agent_t
end

raw(d::Device) = d.agent

handle(d::Device)::UInt64 = d.agent.handle

is_valid(d::Device)::Bool = handle(d) != 0

type(d::Device)::hsa_device_type_t = get_info(raw(d), HSA_AGENT_INFO_DEVICE)

name(d::Device)::String = get_info(raw(d), HSA_AGENT_INFO_NAME)

vendor(d::Device)::String = get_info(raw(d), HSA_AGENT_INFO_VENDOR_NAME)

uuid(d::Device)::String = get_info(raw(d), HSA_AMD_AGENT_INFO_UUID)

product_name(d::Device)::String = get_info(raw(d), HSA_AMD_AGENT_INFO_PRODUCT_NAME)

compute_unit_count(d::Device)::UInt32 = get_info(raw(d), HSA_AMD_AGENT_INFO_COMPUTE_UNIT_COUNT)

num_simds_per_cu(d::Device)::UInt32 = get_info(raw(d), HSA_AMD_AGENT_INFO_NUM_SIMDS_PER_CU)

min_queue_size(d::Device)::UInt32 = get_info(raw(d), HSA_AGENT_INFO_QUEUE_MIN_SIZE)

max_queue_size(d::Device)::UInt32 = get_info(raw(d), HSA_AGENT_INFO_QUEUE_MAX_SIZE)

queue_type(d::Device)::hsa_queue_type_t = get_info(raw(d), HSA_AGENT_INFO_QUEUE_TYPE)

wavefront_size(d::Device)::UInt32 = get_info(raw(d), HSA_AGENT_INFO_WAVEFRONT_SIZE)

workgroup_max_dim(d::Device)::UInt32 = get_info(raw(d), HSA_AGENT_INFO_WORKGROUP_MAX_DIM)

workgroup_max_size(d::Device)::UInt32 = get_info(raw(d), HSA_AGENT_INFO_WORKGROUP_MAX_SIZE)

is_gpu(d::Device)::Bool = type(d) == HSA_DEVICE_TYPE_GPU

function get_devices()
    function _callback(agent::hsa_agent_t, data::Vector{Device})
        push!(data, Device(agent))
        return HSA_STATUS_SUCCESS
    end
    ccallback = @cfunction($_callback,
        hsa_status_t, (hsa_agent_t, Ref{Vector{Device}}))
    devices = Ref(Vector{Device}())
    hsa_iterate_agents(ccallback, devices) |> check
    devices[]
end

# Default device.

const DEFAULT_DEVICE = Ref{Device}()

function get_default_device()
    isassigned(DEFAULT_DEVICE) || error("Default HSA device is not assigned.")
    DEFAULT_DEVICE[]
end

function set_default_device()
    is_valid(DEFAULT_DEVICE[]) && return
    for device in get_devices()
        if is_gpu(device)
            DEFAULT_DEVICE[] = device
            break
        end
    end
end

Device() = get_default_device()

function Base.show(io::IO, d::Device)
    println(io, """Device @ $(handle(d)) handle
        - Name: $(name(d))
        - Type: $(type(d)) (GPU: $(is_gpu(d)))
        - Vendor: $(vendor(d))
        - UUID: $(uuid(d))
        - Product name: $(product_name(d))
        - Compute unit (CU) count: $(compute_unit_count(d))
        - Num SIMDs per CU: $(num_simds_per_cu(d))
        - Min/max queue size: $(min_queue_size(d))/$(max_queue_size(d))
        - Wavefront size: $(wavefront_size(d))
        - Max workgroup size: $(workgroup_max_size(d))
        - Max workgroup dim: $(workgroup_max_dim(d))
    """)
end
