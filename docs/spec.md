# SpikeRoute specification

## Purpose and scope
A parameterized 2×2 mesh of five-port, single-flit spike routers. Track B is implemented with SystemVerilog, Verilator and cocotb. Track A UVM is an optional commercial-simulator porting skeleton only. The default parameters are four-entry input FIFOs and eight route-table entries.

## Packet and ports
Packet is 32 bits: `{key[31:16], payload[15:0]}`. Ports are `0=N, 1=E, 2=S, 3=W, 4=Local`. A table entry is `{key, mask, port_mask[4:0]}`. Match is `(packet.key & mask) == (entry.key & mask)`; lowest entry index wins. Unmatched mesh input goes straight through the opposite port. Unmatched Local input is dropped and counted. A match with a zero target mask is not forwarded (not intended as a valid table action).

## Ready/valid and FIFO behavior
`in_valid && in_ready` pushes one packet into that input's FIFO. `in_ready` is high iff the FIFO is not full. A packet leaves the head only on a grant; a no-match local packet is dropped at the head. Inputs are independent FIFOs. `out_valid` is a combinational grant indication and `out_data` is held only while the relevant head remains granted; downstream `out_ready` and an available credit are required for grant. The mesh wires a neighbor's `in_ready` to upstream `out_ready`.

## Credit and multicast rules
Each output credit counter resets to FIFO_DEPTH, decrements once per granted packet using that output, increments on `credit_ret`, and saturates at FIFO_DEPTH. The environment must return one credit for each consumed output flit; the counter is defensive against malformed extra returns. A multicast packet is granted only if every selected output independently selects the same input in arbitration, has nonzero credit, and is ready in that cycle. It is therefore all-or-nothing and never partially emitted. Per-output round-robin pointers advance after a grant.

```text
Cycle t:    head valid; route mask selects outputs A and B
            grant[p] = arb_A[p] & arb_B[p] & credit_A & credit_B & ready_A & ready_B
At edge t:  if grant: pop input FIFO once; emit identical flit on A and B
            else:     retain FIFO head; emit on neither target
Credit:     downstream FIFO pop -> one-cycle credit_ret to upstream output
```

## 2×2 mesh wiring
Coordinates use router index `x + 2*y`: R0=(0,0), R1=(1,0), R2=(0,1), R3=(1,1). Internal links connect R0.N↔R2.S, R0.E↔R1.W, R1.N↔R3.S, R2.E↔R3.W. Edge order is S0,W0,S1,E1,N2,W2,N3,E3. The wrapper returns internal-link credits from the downstream FIFO's `fifo_pop`; edge and local sinks return credits via explicit inputs.

## Counters
`forwarded_cnt` counts input packets granted (one multicast counts once); `dropped_cnt` counts local unmatched packets; `stalled_cnt` increments each cycle with at least one valid head not popped. They are 32-bit modulo counters.

## Verification contract and limitations
Cocotb tests exercise table unicast, default route, local drop, 2- and 4-way atomic multicast, credit exhaustion/recovery, and a directed R0→R1 mesh transfer. SymbiYosys proves by k-induction, for a reduced single-router instance, FIFO and credit bounds and grant/output consistency. **Not proven:** exact end-to-end packet conservation for arbitrary traffic, bounded RR fairness, or whole-mesh deadlock freedom. The CDG script is a static graph checker with self-tests, not a proof for arbitrary live traffic; routing tables must be supplied/checked under the documented abstraction. Simulation results currently are smoke evidence only, not uniform-random/hotspot/bursty saturation sweeps.

## Timing diagram (input and output)
```text
             t0       t1       t2
in_valid      1        1        0
in_ready      1        1        1
input action  push P   push Q   idle
out_valid     0        1        1
out_ready     1        1        1
credit        4        4        3
output action -        P        Q
```
A push is accepted on a rising edge when valid and ready are both high. A granted output consumes one credit on that edge. The local output sink must assert `local_credit_ret` after consuming the beat; the mesh wrapper handles internal-link credit return automatically.
