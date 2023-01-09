function _find_device_lib_path(lib::String)
    bitcode_dir = ROCmDeviceLibs_jll.bitcode_path
    lib_path = joinpath(bitcode_dir, lib * ".bc")
    ispath(lib_path) && return lib_path
    return ""
end

# NOTE:
# It seems we need to load in reverse order,
# to avoid LLVM deleting the globals from the module, before we use them.
const _DEVICE_LIBS::NTuple{6, String} = (
    "hc", "hip", "irif", "ockl", "opencl", "ocml")

const _DEVICE_LIBS_PATHS::Dict{String, String} = Dict{String, String}(
    lib => _find_device_lib_path(lib) for lib in _DEVICE_LIBS)

# TODO: add methods for global config?
const _OPTION_LIBRARIES::Dict{Symbol, Bool} = Dict{Symbol, Bool}(
    :finite_only => false,
    :unsafe_math => false,
    :correctly_rounded_sqrt => true,
    :daz_opt => false,
    :wavefrontsize64 => true)

function link_device_libs!(target, mod::LLVM.Module)
    # Load & link device libraries.
    for lib in _DEVICE_LIBS
        lib_path = _DEVICE_LIBS_PATHS[lib]
        if isempty(lib_path)
            @debug "Could not find device library: $lib. Skipping it."
            continue
        end
        load_and_link!(mod, lib_path)
    end

    # Load & link OCLC.
    isa = replace(target.dev_isa, "gfx" => "")
    oclc_lib = "oclc_isa_version_$isa"
    oclc_lib_path = get!(
        () -> _find_device_lib_path(oclc_lib),
        _DEVICE_LIBS_PATHS, oclc_lib)
    @assert !isempty(oclc_lib_path)

    load_and_link!(mod, oclc_lib_path)

    # Load & link options libraries.
    for (option, enabled) in _OPTION_LIBRARIES
        toggle = enabled ? "on" : "off"
        option_lib = "oclc_$(option)_$(toggle)"
        option_lib_path = get!(
            () -> _find_device_lib_path(option_lib),
            _DEVICE_LIBS_PATHS, option_lib)

        if isempty(option_lib_path)
            @debug "Could not find option library: $option_lib. Skipping it."
            continue
        end
        load_and_link!(mod, option_lib_path)
    end
end

function load_and_link!(mod::LLVM.Module, lib_path::String)
    ctx = LLVM.context(mod)
    lib = parse(LLVM.Module, read(lib_path); ctx)

    # TODO insert inline attributes?

    LLVM.triple!(lib, LLVM.triple(mod)) # Override to avoid warnings.
    LLVM.datalayout!(lib, LLVM.datalayout(mod))
    LLVM.link!(mod, lib)
end
