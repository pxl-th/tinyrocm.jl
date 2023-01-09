struct Kernel{F}
    f::F
    executable::HSA.Executable
    kernarg_buffer::HSA.KernargBuffer
    # TODO kernel state

    kernel_object::UInt64
    kernarg_segment_size::UInt32
    kernarg_segment_alignment::UInt32
    group_segment_size::UInt32
    private_segment_size::UInt32
end

function Kernel(f::F, executable::HSA.Executable) where F <: Function
    executable_symbol = HSA.kernel_symbol(executable)

    kernel_object = HSA.kernel_object(executable_symbol)
    kernarg_segment_size = HSA.kernarg_segment_size(executable_symbol)
    kernarg_segment_alignment = HSA.kernarg_segment_alignment(executable_symbol)
    group_segment_size = HSA.group_segment_size(executable_symbol)
    private_segment_size = HSA.private_segment_size(executable_symbol)

    kernarg_buffer = HSA.KernargBuffer(
        executable.device, Int(kernarg_segment_size))

    Kernel(f, executable, kernarg_buffer,
        kernel_object, kernarg_segment_size, kernarg_segment_alignment,
        group_segment_size, private_segment_size)
end

device(k::Kernel) = k.executable.device

function (kernel::Kernel)(
    queue::HSA.Queue, signal::HSA.Signal; groupsize, gridsize,
)
    gp_size, gr_size = normalize_launch(groupsize, gridsize)

    HSA.dispatch!(queue, HSA.hsa_kernel_dispatch_packet_t) do
        HSA.hsa_kernel_dispatch_packet_t(
            UInt16(0), # header will be filled later
            UInt16(3) << UInt16(HSA.HSA_KERNEL_DISPATCH_PACKET_SETUP_DIMENSIONS), # always 3 dims in the grid
            UInt16(gp_size.x), UInt16(gp_size.y), UInt16(gp_size.z),
            UInt16(0), # reserved
            UInt32(gr_size.x), UInt32(gr_size.y), UInt32(gr_size.z),
            kernel.private_segment_size,
            kernel.group_segment_size,
            kernel.kernel_object,
            HSA.raw(kernel.kernarg_buffer),
            UInt64(0), # reserved
            HSA.raw(signal),
        )
    end
end
