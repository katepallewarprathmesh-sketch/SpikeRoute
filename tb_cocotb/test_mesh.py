"""Directed 2x2 mesh integration test: R0 local -> R1 local."""
import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


def get_slice(signal, idx, width):
    return (int(signal.value) >> (idx * width)) & ((1 << width) - 1)


@cocotb.test()
async def two_router_unicast(dut):
    dut.rst_n.value = 0
    dut.local_in_valid.value = 0
    dut.local_in_data.value = 0
    dut.local_out_ready.value = 0xF
    dut.local_credit_ret.value = 0
    dut.edge_in_valid.value = 0
    dut.edge_in_data.value = 0
    dut.edge_out_ready.value = 0xFF
    dut.edge_credit_ret.value = 0
    dut.tbl_we.value = 0
    dut.tbl_idx.value = 0
    dut.tbl_key.value = 0
    dut.tbl_mask.value = 0
    dut.tbl_pm.value = 0
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk)

    # R0 local key 0x1234 -> East; R1 West input key -> Local.
    for router, mask in ((0, 1 << 1), (1, 1 << 4)):
        dut.tbl_idx.value = router * 3
        dut.tbl_key.value = 0x1234 << (router * 16)
        dut.tbl_mask.value = 0xFFFF << (router * 16)
        dut.tbl_pm.value = mask << (router * 5)
        dut.tbl_we.value = 1 << router
        await RisingEdge(dut.clk)
    dut.tbl_we.value = 0
    await RisingEdge(dut.clk)

    packet = (0x1234 << 16) | 0xBEEF
    dut.local_in_data.value = packet  # router 0
    dut.local_in_valid.value = 1
    sim_cycle = 0
    for _ in range(20):
        await RisingEdge(dut.clk)
        sim_cycle += 1
        if int(dut.local_in_ready.value) & 1:
            accepted_cycle = sim_cycle
            break
    else:
        raise AssertionError("R0 local input never ready")
    dut.local_in_valid.value = 0

    for _ in range(80):
        await RisingEdge(dut.clk)
        sim_cycle += 1
        if int(dut.local_out_valid.value) & 0b0010:
            delivery_cycle = sim_cycle
            latency = delivery_cycle - accepted_cycle
            got = get_slice(dut.local_out_data, 1, 32)
            assert got == packet, f"R1 received {got:#010x}, expected {packet:#010x}"
            dut.local_credit_ret.value = 0b0010
            await RisingEdge(dut.clk)
            dut.local_credit_ret.value = 0
            break
    else:
        raise AssertionError("packet did not traverse R0->R1 and reach local sink")

    fwd = [get_slice(dut.forwarded_cnt, r, 32) for r in range(4)]
    assert fwd[0] >= 1 and fwd[1] >= 1, f"forward counters unexpected: {fwd}"
    os.makedirs(os.path.join(os.path.dirname(__file__), "..", "results"), exist_ok=True)
    with open(os.path.join(os.path.dirname(__file__), "..", "results", "mesh_smoke.txt"), "w") as f:
        f.write(f"2x2 mesh R0-local -> R1-local unicast PASS; forwarded counters={fwd}; latency={latency} cycles.\n")
    with open(os.path.join(os.path.dirname(__file__), "..", "results", "latency_throughput.csv"), "w") as f:
        f.write("pattern,offered_rate_flits_per_cycle,fanout,packets,mean_latency_cycles,max_latency_cycles,reciprocal_latency_flits_per_cycle,measurement\n")
        f.write(f"single_unicast,not_swept,1,1,{latency},{latency},{1.0/latency:.6f},one-packet smoke; reciprocal latency is not saturation throughput\n")
