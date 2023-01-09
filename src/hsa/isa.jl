const ISA_INFO_MAP = Dict(
    HSA_ISA_INFO_NAME_LENGTH => UInt32,
    HSA_ISA_INFO_NAME => Vector{UInt8},
    HSA_ISA_INFO_PROFILES => NTuple{2, Bool},
    HSA_ISA_INFO_FAST_F16_OPERATION => Bool,
    HSA_ISA_INFO_WORKGROUP_MAX_DIM => NTuple{3, UInt16},
    HSA_ISA_INFO_WORKGROUP_MAX_SIZE => UInt32,
    HSA_ISA_INFO_GRID_MAX_DIM => hsa_dim3_t,
    HSA_ISA_INFO_GRID_MAX_SIZE => UInt64,
    HSA_ISA_INFO_FBARRIER_MAX_SIZE => UInt32,
)

function get_info(isa::hsa_isa_t, attribute, data)
    hsa_isa_get_info_alt(isa, attribute, data) |> check
end

get_info_map(::hsa_isa_t) = ISA_INFO_MAP

name_length(isa::hsa_isa_t)::UInt32 = get_info(isa, HSA_ISA_INFO_NAME_LENGTH)

fast_f16(isa::hsa_isa_t)::Bool = get_info(isa, HSA_ISA_INFO_FAST_F16_OPERATION)

workgroup_max_dim(isa::hsa_isa_t)::NTuple{3, UInt16} = get_info(isa, HSA_ISA_INFO_WORKGROUP_MAX_DIM)

workgroup_max_size(isa::hsa_isa_t)::UInt32 = get_info(isa, HSA_ISA_INFO_WORKGROUP_MAX_SIZE)

grid_max_dim(isa::hsa_isa_t)::hsa_dim3_t = get_info(isa, HSA_ISA_INFO_GRID_MAX_DIM)

grid_max_size(isa::hsa_isa_t)::UInt64 = get_info(isa, HSA_ISA_INFO_GRID_MAX_SIZE)

fbarrier_max_size(isa::hsa_isa_t)::UInt32 = get_info(isa, HSA_ISA_INFO_FBARRIER_MAX_SIZE)

function profile(isa::hsa_isa_t)::hsa_profile_t
    profiles = get_info(isa, HSA_ISA_INFO_PROFILES)
    profiles[1] ? HSA_PROFILE_BASE : HSA_PROFILE_FULL
end

function name(isa::hsa_isa_t)::String
    len = name_length(isa)
    data = Vector{UInt8}(undef, len)
    get_info(isa, HSA_ISA_INFO_NAME, data)
    String(data)
end

const _isa_regex = r"([a-z]*)-([a-z]*)-([a-z]*)--([a-z0-9]*)([a-zA-Z0-9+\-:]*)"
function llvm_arch_features(isa::hsa_isa_t)
    isa_name = name(isa)
    matches = match(_isa_regex, isa_name)
    isnothing(matches) && error("""Failed to match ISA name pattern.
        - ISA name: $isa_name
        - ISA match pattern: $_isa_regex
    """)

    arch = matches.captures[4]
    features = matches.captures[5]

    if !isempty(features)
        feature_splits = filter( # Select non-empty & ending with '+' features.
            x -> !isempty(x) && (x[end] == '+'),
            split(features, ':'))
        features = join(map(x -> x[1:end - 1], feature_splits))
        features = '+' * features
    end

    arch, features # TODO @memoize
end

function get_isas(device::Device)
    isas = Ref(hsa_isa_t[])
    function _callback(isa::hsa_isa_t, data::Vector{hsa_isa_t})
        push!(data, isa)
        return HSA_STATUS_SUCCESS
    end
    ccallback = @cfunction($_callback,
        hsa_status_t, (hsa_isa_t, Ref{Vector{hsa_isa_t}}))
    hsa_agent_iterate_isas(device.agent, ccallback, isas) |> check
    isas[]
end

function default_isa(device::Device)
    first(get_isas(device))
end

function Base.show(io::IO, isa::hsa_isa_t)
    println(io, """ISA @ $(isa.handle) handle
        - Name: $(name(isa))
        - F16 HSAIL is as fast as F32: $(fast_f16(isa))
        - Max workgroup dim: $(workgroup_max_dim(isa))
        - Max workgroup size: $(workgroup_max_size(isa))
        - Max grid dim: $(grid_max_dim(isa))
        - Max grid size: $(grid_max_size(isa))
        - Max fbarriers per workgroup: $(fbarrier_max_size(isa))
        - LLVM arch features: $(llvm_arch_features(isa))
    """)
end
