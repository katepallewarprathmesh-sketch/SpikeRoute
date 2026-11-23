# Verification plan

| Feature | Test / evidence | Coverage point | Assertion / status |
|---|---|---|---|
| Table unicast and default route | `tb_cocotb/test_router.py` | table hit, opposite-port default | Directed simulation PASS |
| Local no-match | Single-router cocotb | drop count increments | Directed simulation PASS |
| Atomic multicast | Fan-out 2 and 4 | destinations observed same cycle | Formal grant/output consistency PASS; directed sim PASS |
| Credit flow control | Exhaust credits, stall, return one | stall and recovery | Credit bound and nonzero-credit-at-grant proved; directed sim PASS |
| FIFO safety | SymbiYosys reduced single router | count never exceeds depth | k-induction PASS, depth 6 basecase |
| Mesh integration | R0 local to R1 local | 2 routers forward | Directed test PASS |
| Deadlock analysis | CDG checker self-test | acyclic accepted, cyclic rejected | Checker self-test PASS; not whole-network formal proof |
| RR fairness | Not yet implemented | contention requester count | Not claimed/proved |
| Exact packet delivery set | Partial directed checks only | no duplicate/loss across arbitrary flows | Not yet formally proved |
| Random/hotspot/bursty traffic and saturation | Not yet implemented | injection rates, fan-out, port-pair cross | Not claimed; `latency_throughput.csv` explicitly labels single-packet smoke |

Track A UVM is represented by a bring-up README, not a complete UVM environment. Commercial simulator execution is not part of the reproduced evidence.
