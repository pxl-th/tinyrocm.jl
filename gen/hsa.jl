using Clang.Generators
using hsa_rocr_jll

include_dir = normpath(hsa_rocr_jll.artifact_dir, "include")
hsa_dir = joinpath(include_dir, "hsa")
options = load_options("gen/hsa-generator.toml")

args = get_default_args()
push!(args, "-I$include_dir")

headers = [
    joinpath(hsa_dir, header)
    for header in readdir(hsa_dir)
    if header in ("hsa.h", "hsa_ext_amd.h")
]

ctx = create_context(headers, args, options)
build!(ctx)
