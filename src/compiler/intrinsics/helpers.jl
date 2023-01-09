# HSA dispatch packet offsets
const _packet_names = fieldnames(HSA.hsa_kernel_dispatch_packet_t)

const _packet_offsets = fieldoffset.(
    HSA.hsa_kernel_dispatch_packet_t, 1:length(_packet_names))
