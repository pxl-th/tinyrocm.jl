mutable struct Signal
    signal::Ref{hsa_signal_t}
end

function Signal(init::Int64 = 1; device::Union{Nothing, Device} = nothing)
    signal_ref = Ref{hsa_signal_t}()
    if isnothing(device)
        n_consumers, consumers = 0, C_NULL
    else
        n_consumers, consumers = 1, [device.agent]
    end
    hsa_signal_create(init, n_consumers, consumers, signal_ref) |> check

    signal = Signal(signal_ref)

    ref!()
    finalizer(signal) do s
        hsa_signal_destroy(s.signal[]) |> check
        unref!()
    end
    signal
end

raw(s::Signal)::hsa_signal_t = s.signal[]

handle(s::Signal)::hsa_signal_t = s.signal[].handle

# TODO can we load/wait/notify relaxed?

function Base.wait(s::Signal; min_latency::Int64 = 1_000 #= 1 micro-second =#)
    signal = raw(s)
    finished = false

    # TODO support timeout
    # TODO support specific queue (to throw QueueError)
    while !finished
        finished = 0 == hsa_signal_wait_scacquire(
            signal, HSA_SIGNAL_CONDITION_LT, 1,
            min_latency, HSA_WAIT_STATE_BLOCKED)
        # Allow another scheduled task to run.
        # This is especially needed in the case
        # when kernels need to perform HostCalls.
        yield()
    end
end

function Base.notify(s::Signal)
    hsa_signal_store_screlease(raw(s), 0)
end
