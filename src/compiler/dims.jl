struct Dim3
    x::Cuint
    y::Cuint
    z::Cuint
end

Dim3(dims::Integer) = Dim3(dims, Cuint(1), Cuint(1))

Dim3(dims::NTuple{1, <: Integer}) = Dim3(dims[1], Cuint(1), Cuint(1))

Dim3(dims::NTuple{2, <: Integer}) = Dim3(dims[1], dims[2],  Cuint(1))

Dim3(dims::NTuple{3, <: Integer}) = Dim3(dims[1], dims[2],  dims[3])

function Base.getindex(dims::Dim3, idx::Int)
    return idx == 1 ? dims.x :
           idx == 2 ? dims.y :
           idx == 3 ? dims.z :
           error("Invalid dimension: $idx")
end

function is_valid(d::Dim3)
    min_valid = (d.x > 0) && (d.y > 0) && (d.z > 0)
    # TODO max based on device spec
    min_valid
end

function normalize_launch(groupsize, gridsize)
    gp_size, gr_size = Dim3(groupsize), Dim3(gridsize)
    # TODO max based on device spec
    is_valid(gp_size) || error("""
        Group dimensions must all be greater than zero, instead: $gp_size.
        """)
    is_valid(gr_size) || error("""
        Grid dimensions must all be greater than zero, instead: $gr_size.
        """)
    gp_size, gr_size
end
